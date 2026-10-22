import Foundation

/// Monster → CLI (stdin) mesajları. Her biri tek satır JSON + "\n" olarak yazılır.
public enum OutboundMessage: Sendable {
    case userText(String)
    /// Metin + `@yol` içerikleri + ekler (görsel blokları). Ek yoksa `userText` ile aynı satırı üretir.
    case userMessage(UserMessage)
    case initialize(requestId: String)
    case interrupt(requestId: String)
    case setPermissionMode(requestId: String, mode: PermissionMode)
    case setModel(requestId: String, model: String?)
    case permissionDecision(requestId: String, decision: PermissionDecision, request: PermissionRequest)

    public var json: JSONValue {
        switch self {
        case .userText(let text):
            return ["type": "user", "message": ["role": "user", "content": .string(text)]]
        case .userMessage(let message):
            return ["type": "user", "message": ["role": "user", "content": message.content]]
        case .initialize(let id):
            return Self.control(id, ["subtype": "initialize"])
        case .interrupt(let id):
            return Self.control(id, ["subtype": "interrupt"])
        case .setPermissionMode(let id, let mode):
            return Self.control(id, ["subtype": "set_permission_mode", "mode": .string(mode.cliValue)])
        case .setModel(let id, let model):
            return Self.control(id, ["subtype": "set_model", "model": model.map(JSONValue.string) ?? .null])
        case .permissionDecision(let id, let decision, let request):
            let body: JSONValue
            switch decision {
            case .allowOnce:
                body = ["behavior": "allow", "updatedInput": request.input]
            case .allowForSession:
                // Öneriler (ör. setMode acceptEdits / addRules) aynen geri gönderilir; CLI bunları session'a uygular.
                body = ["behavior": "allow", "updatedInput": request.input, "updatedPermissions": .array(request.suggestions)]
            case .deny(let message):
                body = ["behavior": "deny", "message": .string(message)]
            }
            return ["type": "control_response",
                    "response": ["subtype": "success", "request_id": .string(id), "response": body]]
        }
    }

    public func encodedLine() -> Data {
        var data = Data(json.compactString().utf8)
        data.append(0x0A)
        return data
    }

    private static func control(_ id: String, _ request: JSONValue) -> JSONValue {
        ["type": "control_request", "request_id": .string(id), "request": request]
    }
}

public enum PermissionDecision: Sendable, Hashable {
    case allowOnce
    case allowForSession
    case deny(message: String)
}

/// Monster'ın UI'daki izin modları ve CLI karşılıkları.
public enum PermissionMode: String, Sendable, Hashable, CaseIterable, Codable, Identifiable {
    case ask
    case autoEdit
    case fullAccess
    case plan

    public var id: String { rawValue }

    public var cliValue: String {
        switch self {
        case .ask: "default"
        case .autoEdit: "acceptEdits"
        case .fullAccess: "bypassPermissions"
        case .plan: "plan"
        }
    }

    public init?(cliValue: String) {
        switch cliValue {
        case "default", "manual": self = .ask
        case "acceptEdits": self = .autoEdit
        case "bypassPermissions": self = .fullAccess
        case "plan": self = .plan
        default: return nil
        }
    }
}
