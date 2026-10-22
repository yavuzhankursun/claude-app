import Foundation

// `claude -p --output-format stream-json` çıktısının tipli modeli.
// Format G2 spike'ında CLI 2.1.308 ile yakalandı (docs/spike/G2-stream-json.md).
// Kural: bilinmeyen `type`/`subtype` hata değildir, `.unknown` olarak geçer ve yok sayılır.

public struct TokenUsage: Sendable, Hashable, Codable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadInputTokens: Int
    public var cacheCreationInputTokens: Int

    public init(inputTokens: Int = 0, outputTokens: Int = 0, cacheReadInputTokens: Int = 0, cacheCreationInputTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
    }

    init(json: JSONValue?) {
        self.init(
            inputTokens: json?["input_tokens"]?.intValue ?? 0,
            outputTokens: json?["output_tokens"]?.intValue ?? 0,
            cacheReadInputTokens: json?["cache_read_input_tokens"]?.intValue ?? 0,
            cacheCreationInputTokens: json?["cache_creation_input_tokens"]?.intValue ?? 0
        )
    }

    /// Bağlam penceresine giren toplam istem boyutu (girdi + önbellek).
    public var promptTokens: Int { inputTokens + cacheReadInputTokens + cacheCreationInputTokens }
}

public enum ContentBlock: Sendable, Hashable {
    case text(String)
    case thinking(String)
    case redactedThinking
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseId: String, content: ToolResultContent, isError: Bool)
    case image(mediaType: String?)
    case unknown(type: String)

    init(json: JSONValue) {
        switch json["type"]?.stringValue {
        case "text":
            self = .text(json["text"]?.stringValue ?? "")
        case "thinking":
            self = .thinking(json["thinking"]?.stringValue ?? "")
        case "redacted_thinking":
            self = .redactedThinking
        case "tool_use", "server_tool_use":
            self = .toolUse(
                id: json["id"]?.stringValue ?? "",
                name: json["name"]?.stringValue ?? "?",
                input: json["input"] ?? .object([:])
            )
        case "tool_result":
            self = .toolResult(
                toolUseId: json["tool_use_id"]?.stringValue ?? "",
                content: ToolResultContent(json: json["content"]),
                isError: json["is_error"]?.boolValue ?? false
            )
        case "image":
            self = .image(mediaType: json["source"]?["media_type"]?.stringValue)
        case let other:
            self = .unknown(type: other ?? "?")
        }
    }

    static func list(_ json: JSONValue?) -> [ContentBlock] {
        switch json {
        case .string(let s)?: return [.text(s)]
        case .array(let items)?: return items.map(ContentBlock.init(json:))
        default: return []
        }
    }
}

/// tool_result içeriği düz metin ya da blok listesi olabilir; UI için metne indirgenir.
public struct ToolResultContent: Sendable, Hashable {
    public var text: String
    public var imageCount: Int

    init(json: JSONValue?) {
        switch json {
        case .string(let s)?:
            text = s
            imageCount = 0
        case .array(let items)?:
            text = items.compactMap { $0["type"]?.stringValue == "text" ? $0["text"]?.stringValue : nil }
                .joined(separator: "\n")
            imageCount = items.filter { $0["type"]?.stringValue == "image" }.count
        default:
            text = ""
            imageCount = 0
        }
    }

    public init(text: String, imageCount: Int = 0) {
        self.text = text
        self.imageCount = imageCount
    }
}

public struct SessionInit: Sendable, Hashable {
    public var sessionId: String
    public var model: String?
    public var cwd: String?
    public var permissionMode: String?
    public var cliVersion: String?
    public var tools: [String]
    public var apiKeySource: String?
}

/// Abonelik plan limitleri (`rate_limit_event.rate_limit_info.unifiedWindows`). `utilization` 0…1.
public enum PlanLimitKind: String, Sendable, Hashable, CaseIterable {
    case fiveHour = "five_hour"
    case sevenDay = "seven_day"
}

public struct PlanLimit: Sendable, Hashable {
    public var utilization: Double
    public var resetsAt: Date?
}

public struct ResultInfo: Sendable, Hashable {
    public var subtype: String
    public var isError: Bool
    public var resultText: String?
    public var sessionId: String?
    public var totalCostUSD: Double?
    public var durationMs: Int?
    public var timeToFirstTokenMs: Int?
    public var numTurns: Int?
    public var stopReason: String?
    public var usage: TokenUsage
    /// `modelUsage.<model>.contextWindow`, model adına göre. Ana modelin penceresi reducer'da seçilir
    /// (alt ajanlar başka bir modelle çalışabilir).
    public var contextWindows: [String: Int]
    public var permissionDenialCount: Int
}

public struct PermissionRequest: Sendable, Hashable, Identifiable {
    public var id: String { requestId }
    public var requestId: String
    public var toolName: String
    public var displayName: String
    public var input: JSONValue
    public var description: String?
    public var toolUseId: String?
    /// CLI'ın önerdiği kalıcı kurallar ("Bu session için" seçeneğinde aynen geri gönderilir).
    public var suggestions: [JSONValue]

    public init(requestId: String, toolName: String, displayName: String? = nil, input: JSONValue,
                description: String? = nil, toolUseId: String? = nil, suggestions: [JSONValue] = []) {
        self.requestId = requestId
        self.toolName = toolName
        self.displayName = displayName ?? toolName
        self.input = input
        self.description = description
        self.toolUseId = toolUseId
        self.suggestions = suggestions
    }
}

public enum StreamDelta: Sendable, Hashable {
    case text(String)
    case thinking(String)
    case inputJSON(String)
    case signature
    case other(String)
}

public enum StreamBlockKind: Sendable, Hashable {
    case text
    case thinking
    case toolUse(id: String, name: String)
    case other(String)
}

/// Anthropic Messages API'nin ham streaming event'leri (`--include-partial-messages`).
public enum StreamEvent: Sendable, Hashable {
    case messageStart(messageId: String, usage: TokenUsage)
    case blockStart(index: Int, kind: StreamBlockKind)
    case blockDelta(index: Int, delta: StreamDelta)
    case blockStop(index: Int)
    case messageDelta(stopReason: String?, usage: TokenUsage)
    case messageStop
    case unknown(String)

    init(json: JSONValue) {
        let index = json["index"]?.intValue ?? 0
        switch json["type"]?.stringValue {
        case "message_start":
            self = .messageStart(
                messageId: json["message"]?["id"]?.stringValue ?? "",
                usage: TokenUsage(json: json["message"]?["usage"])
            )
        case "content_block_start":
            let block = json["content_block"]
            let kind: StreamBlockKind
            switch block?["type"]?.stringValue {
            case "text": kind = .text
            case "thinking": kind = .thinking
            case "tool_use", "server_tool_use":
                kind = .toolUse(id: block?["id"]?.stringValue ?? "", name: block?["name"]?.stringValue ?? "?")
            case let other: kind = .other(other ?? "?")
            }
            self = .blockStart(index: index, kind: kind)
        case "content_block_delta":
            let delta = json["delta"]
            switch delta?["type"]?.stringValue {
            case "text_delta": self = .blockDelta(index: index, delta: .text(delta?["text"]?.stringValue ?? ""))
            case "thinking_delta": self = .blockDelta(index: index, delta: .thinking(delta?["thinking"]?.stringValue ?? ""))
            case "input_json_delta": self = .blockDelta(index: index, delta: .inputJSON(delta?["partial_json"]?.stringValue ?? ""))
            case "signature_delta": self = .blockDelta(index: index, delta: .signature)
            case let other: self = .blockDelta(index: index, delta: .other(other ?? "?"))
            }
        case "content_block_stop":
            self = .blockStop(index: index)
        case "message_delta":
            self = .messageDelta(stopReason: json["delta"]?["stop_reason"]?.stringValue, usage: TokenUsage(json: json["usage"]))
        case "message_stop":
            self = .messageStop
        case let other:
            self = .unknown(other ?? "?")
        }
    }
}

public enum InboundMessage: Sendable, Hashable {
    case systemInit(SessionInit)
    /// `system/status`: `requesting` vb. durum ve izin modu değişikliği.
    case status(status: String?, permissionMode: String?)
    /// CLI'ın tur sonu tek satır özeti (`system/post_turn_summary`).
    case turnSummary(String)
    case system(subtype: String)
    case stream(StreamEvent, messageId: String?, parentToolUseId: String?)
    case assistant(messageId: String, content: [ContentBlock], usage: TokenUsage, parentToolUseId: String?)
    case user(content: [ContentBlock], parentToolUseId: String?)
    case result(ResultInfo)
    case permissionRequest(PermissionRequest)
    case controlRequest(requestId: String, subtype: String)
    case controlResponse(requestId: String, success: Bool, payload: JSONValue?, error: String?)
    case controlCancel(requestId: String)
    case rateLimit(status: String?, utilization: Double?, resetsAt: Date?, windows: [PlanLimitKind: PlanLimit])
    case unknown(type: String)

    public init(json: JSONValue) {
        let parent = json["parent_tool_use_id"]?.stringValue
        switch json["type"]?.stringValue {
        case "system":
            switch json["subtype"]?.stringValue {
            case "init":
                self = .systemInit(SessionInit(
                    sessionId: json["session_id"]?.stringValue ?? "",
                    model: json["model"]?.stringValue,
                    cwd: json["cwd"]?.stringValue,
                    permissionMode: json["permissionMode"]?.stringValue,
                    cliVersion: json["claude_code_version"]?.stringValue,
                    tools: json["tools"]?.arrayValue?.compactMap(\.stringValue) ?? [],
                    apiKeySource: json["apiKeySource"]?.stringValue
                ))
            case "status":
                self = .status(status: json["status"]?.stringValue, permissionMode: json["permissionMode"]?.stringValue)
            case "post_turn_summary":
                self = .turnSummary(json["status_detail"]?.stringValue ?? "")
            case let other:
                self = .system(subtype: other ?? "?")
            }
        case "stream_event":
            self = .stream(
                StreamEvent(json: json["event"] ?? .null),
                messageId: json["api_message_id"]?.stringValue,
                parentToolUseId: parent
            )
        case "assistant":
            let message = json["message"]
            self = .assistant(
                messageId: message?["id"]?.stringValue ?? "",
                content: ContentBlock.list(message?["content"]),
                usage: TokenUsage(json: message?["usage"]),
                parentToolUseId: parent
            )
        case "user":
            self = .user(content: ContentBlock.list(json["message"]?["content"]), parentToolUseId: parent)
        case "result":
            let modelUsage = json["modelUsage"]?.objectValue ?? [:]
            let windows = modelUsage.compactMapValues { $0["contextWindow"]?.intValue }
            self = .result(ResultInfo(
                subtype: json["subtype"]?.stringValue ?? "?",
                isError: json["is_error"]?.boolValue ?? false,
                resultText: json["result"]?.stringValue,
                sessionId: json["session_id"]?.stringValue,
                totalCostUSD: json["total_cost_usd"]?.doubleValue,
                durationMs: json["duration_ms"]?.intValue,
                timeToFirstTokenMs: json["ttft_ms"]?.intValue,
                numTurns: json["num_turns"]?.intValue,
                stopReason: json["stop_reason"]?.stringValue,
                usage: TokenUsage(json: json["usage"]),
                contextWindows: windows,
                permissionDenialCount: json["permission_denials"]?.arrayValue?.count ?? 0
            ))
        case "control_request":
            let requestId = json["request_id"]?.stringValue ?? ""
            let request = json["request"]
            let subtype = request?["subtype"]?.stringValue ?? "?"
            if subtype == "can_use_tool" {
                let toolName = request?["tool_name"]?.stringValue ?? "?"
                self = .permissionRequest(PermissionRequest(
                    requestId: requestId,
                    toolName: toolName,
                    displayName: request?["display_name"]?.stringValue,
                    input: request?["input"] ?? .object([:]),
                    description: request?["description"]?.stringValue,
                    toolUseId: request?["tool_use_id"]?.stringValue,
                    suggestions: request?["permission_suggestions"]?.arrayValue ?? []
                ))
            } else {
                self = .controlRequest(requestId: requestId, subtype: subtype)
            }
        case "control_response":
            let response = json["response"]
            self = .controlResponse(
                requestId: response?["request_id"]?.stringValue ?? "",
                success: response?["subtype"]?.stringValue == "success",
                payload: response?["response"],
                error: response?["error"]?.stringValue
            )
        case "control_cancel_request":
            self = .controlCancel(requestId: json["request_id"]?.stringValue ?? "")
        case "rate_limit_event":
            let info = json["rate_limit_info"]
            var windows: [PlanLimitKind: PlanLimit] = [:]
            for kind in PlanLimitKind.allCases {
                guard let window = info?["unifiedWindows"]?[kind.rawValue],
                      let utilization = window["utilization"]?.doubleValue else { continue }
                windows[kind] = PlanLimit(
                    utilization: utilization,
                    resetsAt: window["resetsAt"]?.doubleValue.map { Date(timeIntervalSince1970: $0) })
            }
            self = .rateLimit(
                status: info?["status"]?.stringValue,
                utilization: info?["utilization"]?.doubleValue,
                resetsAt: info?["resetsAt"]?.doubleValue.map { Date(timeIntervalSince1970: $0) },
                windows: windows
            )
        case let other:
            self = .unknown(type: other ?? "?")
        }
    }

    /// Tek bir NDJSON satırını çözer. Bozuk satır `nil` döner (akış durmaz).
    public static func decode(line: some DataProtocol) -> InboundMessage? {
        guard let value = try? JSONValue.parse(Data(line)) else { return nil }
        return InboundMessage(json: value)
    }
}
