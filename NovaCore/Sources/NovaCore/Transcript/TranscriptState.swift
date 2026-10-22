import Foundation

/// Bir session'ın görünür durumu. Saf değer tipi: `apply(_:)` ile ilerler, UI kare başına bir kez kopyasını alır.
///
/// Uzlaştırma kuralı (spike bulgusu): `--include-partial-messages` ile her blok önce `stream_event` olarak akar,
/// ardından aynı `message.id` ile blok başına bir `assistant` satırı gelir. Akışını gördüğümüz mesajların
/// `assistant` satırları yalnızca araç girdisini kesinleştirmek için kullanılır; görmediklerimiz (geçmiş, alt ajan
/// dışı yeniden bağlanma) doğrudan eklenir. Böylece aynı içerik iki kez görünmez.
public struct TranscriptState: Sendable {
    public private(set) var items: [TranscriptItem] = []
    private var positions: [String: Int] = [:]

    public private(set) var sessionId: String?
    public private(set) var model: String?
    public private(set) var cliVersion: String?
    public private(set) var permissionMode: PermissionMode?
    public private(set) var isTurnActive = false
    public private(set) var pendingPermissions: [PermissionRequest] = []
    public private(set) var lastTurnSummary: String?
    public private(set) var lastResult: ResultInfo?

    // Kullanım
    public private(set) var totalCostUSD: Double = 0
    public private(set) var contextTokens: Int = 0
    public private(set) var contextWindow: Int = 200_000
    public private(set) var outputTokensThisTurn: Int = 0
    public private(set) var rateLimitUtilization: Double?

    // Akış takibi
    private var streamedMessageIds: Set<String> = []
    private var currentMessageId: String?
    private var streamBlocks: [Int: String] = [:]
    private var blockCounters: [String: Int] = [:]
    private var deniedToolUseIds: Set<String> = []
    private var userCounter = 0
    private var interruptRequested = false
    private var turnStartIndex = 0

    public init() {}

    public var contextFraction: Double {
        guard contextWindow > 0 else { return 0 }
        return min(1, Double(contextTokens) / Double(contextWindow))
    }

    public func item(id: String) -> TranscriptItem? {
        positions[id].map { items[$0] }
    }

    // MARK: - Yerel olaylar (UI'dan)

    /// Kullanıcı mesajı gönderildiğinde hemen gösterilir (CLI canlı modda kullanıcı mesajını yankılamaz).
    public mutating func appendLocalUserMessage(_ text: String) {
        turnStartIndex = items.count
        appendUser(text)
        isTurnActive = true
        outputTokensThisTurn = 0
    }

    /// Esc/Durdur: sonraki hata `result`'ı hata değil "durduruldu" olarak gösterilir.
    public mutating func markInterruptRequested() {
        interruptRequested = true
    }

    public mutating func recordPermissionDecision(_ request: PermissionRequest, decision: PermissionDecision) {
        pendingPermissions.removeAll { $0.requestId == request.requestId }
        guard let toolUseId = request.toolUseId else { return }
        switch decision {
        case .allowOnce, .allowForSession:
            updateTool(toolUseId) { $0.status = .running }
        case .deny:
            deniedToolUseIds.insert(toolUseId)
            updateTool(toolUseId) { $0.status = .denied }
        }
    }

    public mutating func markProcessExited(error: String?) {
        if isTurnActive, let error { append(TranscriptItem(id: "exit-\(items.count)", kind: .notice(.error(error)))) }
        isTurnActive = false
        pendingPermissions.removeAll()
        finishOpenItems(cancelTools: true)
    }

    // MARK: - CLI olayları

    public mutating func apply(_ message: InboundMessage) {
        switch message {
        case .systemInit(let info):
            sessionId = info.sessionId
            model = info.model
            cliVersion = info.cliVersion
            if let mode = info.permissionMode { permissionMode = PermissionMode(cliValue: mode) }

        case .status(_, let mode):
            if let mode, let parsed = PermissionMode(cliValue: mode) { permissionMode = parsed }

        case .turnSummary(let text):
            if !text.isEmpty { lastTurnSummary = text }

        case .stream(let event, let messageId, let parent):
            if let parent {
                updateTool(parent) { $0.subagentMessageCount += event.isMessageStart ? 1 : 0 }
                return
            }
            applyStream(event, messageId: messageId)

        case .assistant(let messageId, let content, let usage, let parent):
            if let parent {
                updateTool(parent) { $0.subagentMessageCount += 1 }
                return
            }
            applyAssistant(messageId: messageId, content: content, usage: usage)

        case .user(let content, let parent):
            if parent != nil { return }
            applyUser(content)

        case .result(let info):
            lastResult = info
            isTurnActive = false
            if let cost = info.totalCostUSD { totalCostUSD += cost }
            if let window = info.contextWindow, window > 0 { contextWindow = window }
            if info.isError, interruptRequested, !containsInterruptNoticeThisTurn {
                append(TranscriptItem(id: "int-\(items.count)", kind: .notice(.interrupted)))
            } else if info.isError, info.subtype != "success", !interruptRequested {
                let text = info.resultText.flatMap { $0.isEmpty ? nil : $0 } ?? info.subtype
                append(TranscriptItem(id: "result-\(items.count)", kind: .notice(.error(text))))
            }
            pendingPermissions.removeAll()
            finishOpenItems(cancelTools: info.isError)
            interruptRequested = false
            turnStartIndex = items.count

        case .permissionRequest(let request):
            pendingPermissions.removeAll { $0.requestId == request.requestId }
            pendingPermissions.append(request)
            if let toolUseId = request.toolUseId {
                if positions[toolUseId] == nil {
                    append(TranscriptItem(id: toolUseId, kind: .toolCall(ToolCall(
                        id: toolUseId, name: request.toolName, input: request.input, status: .awaitingPermission))))
                } else {
                    updateTool(toolUseId) {
                        $0.status = .awaitingPermission
                        if $0.input == nil { $0.input = request.input }
                    }
                }
            }

        case .controlCancel(let requestId):
            pendingPermissions.removeAll { $0.requestId == requestId }

        case .rateLimit(_, let utilization, _):
            rateLimitUtilization = utilization

        case .system, .controlRequest, .controlResponse, .unknown:
            break
        }
    }

    // MARK: - Ayrıntılar

    private mutating func applyStream(_ event: StreamEvent, messageId: String?) {
        switch event {
        case .messageStart(let id, let usage):
            currentMessageId = id
            streamedMessageIds.insert(id)
            streamBlocks.removeAll()
            isTurnActive = true
            contextTokens = usage.promptTokens + usage.outputTokens

        case .blockStart(let index, let kind):
            let mid = messageId ?? currentMessageId ?? "m"
            switch kind {
            case .text:
                let id = "\(mid)#\(index)"
                streamBlocks[index] = id
                append(TranscriptItem(id: id, kind: .assistantText(""), isStreaming: true))
            case .thinking:
                let id = "\(mid)#\(index)"
                streamBlocks[index] = id
                append(TranscriptItem(id: id, kind: .thinking("", isStreaming: true), isStreaming: true))
            case .toolUse(let toolId, let name):
                streamBlocks[index] = toolId
                if positions[toolId] == nil {
                    append(TranscriptItem(id: toolId, kind: .toolCall(ToolCall(id: toolId, name: name, status: .streamingInput)),
                                          isStreaming: true))
                }
            case .other:
                break
            }

        case .blockDelta(let index, let delta):
            guard let id = streamBlocks[index], let pos = positions[id] else { return }
            switch (items[pos].kind, delta) {
            case (.assistantText(let text), .text(let more)):
                items[pos].kind = .assistantText(text + more)
            case (.thinking(let text, _), .thinking(let more)):
                items[pos].kind = .thinking(text + more, isStreaming: true)
            case (.toolCall(var call), .inputJSON(let more)):
                call.partialInput += more
                items[pos].kind = .toolCall(call)
            default:
                break
            }

        case .blockStop(let index):
            guard let id = streamBlocks[index], let pos = positions[id] else { return }
            items[pos].isStreaming = false
            switch items[pos].kind {
            case .thinking(let text, _):
                items[pos].kind = .thinking(text, isStreaming: false)
            case .toolCall(var call):
                if call.input == nil, let parsed = try? JSONValue.parse(call.partialInput.isEmpty ? "{}" : call.partialInput) {
                    call.input = parsed
                }
                if call.status == .streamingInput { call.status = .running }
                items[pos].kind = .toolCall(call)
            default:
                break
            }

        case .messageDelta(_, let usage):
            outputTokensThisTurn += usage.outputTokens
            if usage.promptTokens > 0 { contextTokens = usage.promptTokens + usage.outputTokens }

        case .messageStop:
            streamBlocks.removeAll()

        case .unknown:
            break
        }
    }

    private mutating func applyAssistant(messageId: String, content: [ContentBlock], usage: TokenUsage) {
        if streamedMessageIds.contains(messageId) {
            // Akışı zaten gösterildi; yalnızca araç girdisini kesinleştir.
            for case .toolUse(let id, _, let input) in content {
                updateTool(id) { $0.input = input }
            }
            return
        }
        if usage.promptTokens > 0 { contextTokens = usage.promptTokens + usage.outputTokens }
        for block in content {
            let seq = blockCounters[messageId, default: 0]
            blockCounters[messageId] = seq + 1
            let id = "\(messageId)#h\(seq)"
            switch block {
            case .text(let text):
                if !text.isEmpty { append(TranscriptItem(id: id, kind: .assistantText(text))) }
            case .thinking(let text):
                if !text.isEmpty { append(TranscriptItem(id: id, kind: .thinking(text, isStreaming: false))) }
            case .redactedThinking:
                append(TranscriptItem(id: id, kind: .redactedThinking))
            case .toolUse(let toolId, let name, let input):
                if positions[toolId] == nil {
                    append(TranscriptItem(id: toolId, kind: .toolCall(ToolCall(id: toolId, name: name, input: input, status: .running))))
                } else {
                    updateTool(toolId) { $0.input = input }
                }
            case .toolResult, .image, .unknown:
                break
            }
        }
    }

    private mutating func applyUser(_ content: [ContentBlock]) {
        for block in content {
            switch block {
            case .toolResult(let toolUseId, let result, let isError):
                let wasDenied = deniedToolUseIds.contains(toolUseId)
                updateTool(toolUseId) { call in
                    call.result = result
                    call.status = wasDenied ? .denied : (isError ? .failed : .succeeded)
                }
            case .text(let text):
                if text.hasPrefix("[Request interrupted") {
                    append(TranscriptItem(id: "int-\(items.count)", kind: .notice(.interrupted)))
                } else if !Self.isSyntheticUserText(text) {
                    appendUser(text)
                }
            default:
                break
            }
        }
    }

    /// CLI'ın kullanıcı rolüyle yazdığı ama kullanıcıya ait olmayan metinler (komut çıktıları, uyarılar).
    static func isSyntheticUserText(_ text: String) -> Bool {
        let markers = ["<command-name>", "<local-command-stdout>", "<command-message>", "<system-reminder>",
                       "Caveat: The messages below"]
        return markers.contains { text.hasPrefix($0) }
    }

    private var containsInterruptNoticeThisTurn: Bool {
        items[min(turnStartIndex, items.count)...].contains { item in
            if case .notice(.interrupted) = item.kind { return true }
            return false
        }
    }

    private mutating func appendUser(_ text: String) {
        userCounter += 1
        append(TranscriptItem(id: "user-\(userCounter)", kind: .user(text)))
    }

    private mutating func append(_ item: TranscriptItem) {
        if let existing = positions[item.id] {
            items[existing] = item
            return
        }
        positions[item.id] = items.count
        items.append(item)
    }

    private mutating func updateTool(_ id: String, _ body: (inout ToolCall) -> Void) {
        guard let pos = positions[id], case .toolCall(var call) = items[pos].kind else { return }
        body(&call)
        items[pos].kind = .toolCall(call)
    }

    private mutating func finishOpenItems(cancelTools: Bool) {
        for pos in items.indices where items[pos].isStreaming || isOpenTool(items[pos]) {
            items[pos].isStreaming = false
            switch items[pos].kind {
            case .thinking(let text, _):
                items[pos].kind = .thinking(text, isStreaming: false)
            case .toolCall(var call) where !call.status.isTerminal:
                call.status = cancelTools ? .cancelled : call.status
                items[pos].kind = .toolCall(call)
            default:
                break
            }
        }
        streamBlocks.removeAll()
    }

    private func isOpenTool(_ item: TranscriptItem) -> Bool {
        if case .toolCall(let call) = item.kind { return !call.status.isTerminal }
        return false
    }
}

private extension StreamEvent {
    var isMessageStart: Bool {
        if case .messageStart = self { return true }
        return false
    }
}
