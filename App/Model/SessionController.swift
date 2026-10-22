import Foundation
import NovaCore
import Observation
import os

/// Tek bir session'ın canlı durumu. CLI olaylarını `TranscriptState`e uygular ve UI'a kare hızında yayınlar:
/// her token'da değil, en fazla ~60 Hz'de bir gözlem bildirimi (docs/adr/0004-design-system.md, "Akıcılık").
@Observable
final class SessionController: Identifiable {
    enum Phase: Equatable {
        case idle
        case starting
        case ready
        case exited(String?)
    }

    let id: UUID
    let record: SessionRecord

    private(set) var transcript = TranscriptState()
    private(set) var phase: Phase = .idle
    private(set) var lastError: String?
    /// Kullanıcı Gönder'e bastıktan sonra ilk metin token'ının ekrana basılma süresi.
    private(set) var lastFirstTokenLatency: Duration?
    private(set) var cliVersion: String?
    var draft = ""

    @ObservationIgnored private let engine: AgentEngine
    @ObservationIgnored private let history: HistoryIndexer
    @ObservationIgnored private var working = TranscriptState()
    @ObservationIgnored private var consumeTask: Task<Void, Never>?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var lastPublish = ContinuousClock.now
    @ObservationIgnored private var sendInstant: ContinuousClock.Instant?
    @ObservationIgnored private var historyLoaded = false
    @ObservationIgnored private let log = Logger(subsystem: "app.nova", category: "session")

    /// 60 Hz: 16.6 ms. Akış sırasında en sık bu aralıkla yayınlanır.
    static let frameBudget: Duration = .milliseconds(16)

    init(record: SessionRecord, engine: AgentEngine, history: HistoryIndexer) {
        self.id = record.id
        self.record = record
        self.engine = engine
        self.history = history
    }

    var isTurnActive: Bool { transcript.isTurnActive }
    var pendingPermission: PermissionRequest? { transcript.pendingPermissions.first }
    var isLive: Bool { phase == .ready || phase == .starting }

    // MARK: - Yaşam döngüsü

    /// Geçmişi yükler (varsa). Seçildiğinde çağrılır; büyük dosyalar ana thread dışında çözülür.
    func loadHistoryIfNeeded() async {
        guard !historyLoaded else { return }
        historyLoaded = true
        guard let url = history.fileURL(forSession: record.cliSessionId) else { return }
        let loaded = await Task.detached(priority: .userInitiated) { try? HistoryLoader.load(url) }.value
        guard let loaded, working.items.isEmpty else { return }
        working = loaded
        transcript = loaded
    }

    /// Süreci önceden başlatır; ilk mesajda spawn gecikmesi ödenmez.
    func prewarm() async {
        guard phase == .idle || isExited else { return }
        await start()
    }

    private var isExited: Bool {
        if case .exited = phase { return true }
        return false
    }

    private func start() async {
        phase = .starting
        let hasTranscriptOnDisk = history.fileURL(forSession: record.cliSessionId) != nil
        let config = LaunchConfiguration(
            mode: record.mode,
            workingDirectory: record.workingDirectory,
            model: record.model,
            effort: record.effort,
            permissionMode: record.permissionMode,
            resumeSessionId: hasTranscriptOnDisk ? record.cliSessionId : nil,
            newSessionId: hasTranscriptOnDisk ? nil : record.cliSessionId
        )
        do {
            let handle = try await engine.start(id: id, configuration: config)
            phase = .ready
            lastError = nil
            consumeTask?.cancel()
            consumeTask = Task { [weak self] in
                for await event in handle.events {
                    guard let self else { return }
                    self.handle(event)
                }
            }
        } catch {
            phase = .exited(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func stopProcess() async {
        await engine.stop(id)
        consumeTask?.cancel()
        consumeTask = nil
        working.markProcessExited(error: nil)
        publish(force: true)
        phase = .idle
    }

    // MARK: - Kullanıcı eylemleri

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !working.isTurnActive else { return }
        draft = ""
        if !isLive { await start() }
        guard phase == .ready else {
            draft = text
            return
        }
        working.appendLocalUserMessage(text)
        sendInstant = .now
        publish(force: true)
        if record.title.isEmpty || record.title == SessionTitles.placeholder {
            record.title = SessionTitles.make(from: text)
        }
        record.lastActiveAt = .now
        do {
            try await engine.sendUserMessage(text, to: id)
        } catch {
            working.markProcessExited(error: error.localizedDescription)
            publish(force: true)
        }
    }

    func interrupt() async {
        guard working.isTurnActive else { return }
        working.markInterruptRequested()
        try? await engine.interrupt(id)
    }

    func decide(_ decision: PermissionDecision, for request: PermissionRequest) async {
        working.recordPermissionDecision(request, decision: decision)
        publish(force: true)
        do {
            try await engine.respond(to: request, with: decision, in: id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setPermissionMode(_ mode: PermissionMode) async {
        guard record.mode == .code else { return }
        record.permissionMode = mode
        if isLive { try? await engine.setPermissionMode(mode, in: id) }
    }

    func setModel(_ model: String?) async {
        record.model = model
        if isLive { try? await engine.setModel(model, in: id) }
    }

    // MARK: - Olay işleme

    private func handle(_ event: ClaudeProcess.Event) {
        switch event {
        case .message(let message):
            if case .systemInit(let info) = message { cliVersion = info.cliVersion }
            let wasEmpty = !hasVisibleAssistantText
            working.apply(message)
            if let sent = sendInstant, wasEmpty, hasVisibleAssistantText {
                lastFirstTokenLatency = .now - sent
                sendInstant = nil
                if let latency = lastFirstTokenLatency {
                    log.info("first token latency=\(latency.milliseconds, format: .fixed(precision: 1), privacy: .public)ms")
                }
            }
            publish(force: Self.isUrgent(message))
        case .malformedLine(let bytes):
            log.debug("malformed line bytes=\(bytes, privacy: .public)")
        case .exited(let status, _, let stderrTail):
            let message: String? = status == 0 ? nil : Self.exitMessage(status: status, stderr: stderrTail)
            working.markProcessExited(error: message)
            phase = .exited(message)
            lastError = message
            publish(force: true)
            Task { await engine.forget(id) }
        }
    }

    /// Bir sonraki karede gösterilmesi beklenmeyecek olaylar (izin, tur sonu) hemen yayınlanır.
    private static func isUrgent(_ message: InboundMessage) -> Bool {
        switch message {
        case .permissionRequest, .result, .systemInit, .status: true
        default: false
        }
    }

    private var hasVisibleAssistantText: Bool {
        guard let last = working.items.last else { return false }
        switch last.kind {
        case .assistantText(let t): return !t.isEmpty
        case .thinking, .toolCall: return true
        default: return false
        }
    }

    private func publish(force: Bool = false) {
        let now = ContinuousClock.now
        if force || now - lastPublish >= Self.frameBudget {
            flushTask?.cancel()
            flushTask = nil
            transcript = working
            lastPublish = now
            return
        }
        guard flushTask == nil else { return }
        let delay = Self.frameBudget - (now - lastPublish)
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            self.transcript = self.working
            self.lastPublish = .now
            self.flushTask = nil
        }
    }

    private static func exitMessage(status: Int32, stderr: String) -> String {
        let lastLine = stderr.split(separator: "\n").last.map(String.init) ?? ""
        if lastLine.localizedCaseInsensitiveContains("login") || lastLine.localizedCaseInsensitiveContains("auth") {
            return String(localized: "Claude Code oturumu açık değil. Terminalde `claude` çalıştırıp giriş yapın.")
        }
        // stderr içerik barındırabilir; kullanıcıya gösterilir ama loglanmaz.
        return lastLine.isEmpty
            ? String(localized: "Claude süreci beklenmedik şekilde kapandı (kod \(status)).")
            : String(localized: "Claude süreci kapandı (kod \(status)): \(String(lastLine.prefix(300)))")
    }
}

enum SessionTitles {
    static var placeholder: String { String(localized: "Yeni session") }

    static func make(from prompt: String) -> String {
        let oneLine = prompt.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return oneLine.count <= 60 ? oneLine : String(oneLine.prefix(59)) + "…"
    }
}

extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }
}
