import Foundation

public struct ToolCall: Sendable, Hashable, Identifiable {
    public enum Status: Sendable, Hashable {
        /// Model girdiyi hâlâ üretiyor (input_json_delta).
        case streamingInput
        case awaitingPermission
        case running
        case succeeded
        case failed
        case denied
        case cancelled

        public var isTerminal: Bool {
            switch self {
            case .succeeded, .failed, .denied, .cancelled: true
            default: false
            }
        }
    }

    public var id: String
    public var name: String
    /// Akış sırasında biriken ham JSON parçaları.
    public var partialInput: String
    public var input: JSONValue?
    public var result: ToolResultContent?
    public var status: Status
    /// Bu araç (ör. Task/Agent) altında çalışan alt ajan mesajı sayısı.
    public var subagentMessageCount: Int

    public init(id: String, name: String, input: JSONValue? = nil, status: Status) {
        self.id = id
        self.name = name
        self.partialInput = ""
        self.input = input
        self.result = nil
        self.status = status
        self.subagentMessageCount = 0
    }

    /// Kart başlığındaki kısa özet: Bash komutu, dosya yolu, arama kalıbı…
    public var summary: String {
        guard let input else { return "" }
        let keys = ["command", "file_path", "path", "pattern", "url", "query", "description", "prompt", "notebook_path"]
        for key in keys {
            if let value = input[key]?.stringValue, !value.isEmpty {
                return value.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? value
            }
        }
        return ""
    }

    public var kind: ToolKind { ToolKind(name: name) }
}

public enum ToolKind: Sendable, Hashable {
    case bash, read, edit, write, search, web, task, todo, other

    public init(name: String) {
        switch name {
        case "Bash", "BashOutput", "KillShell", "PowerShell": self = .bash
        case "Read", "NotebookRead": self = .read
        case "Edit", "MultiEdit", "NotebookEdit": self = .edit
        case "Write": self = .write
        case "Glob", "Grep", "LS": self = .search
        case "WebFetch", "WebSearch": self = .web
        case "Task", "Agent": self = .task
        case "TodoWrite", "TaskCreate", "TaskUpdate": self = .todo
        default: self = .other
        }
    }

    /// SF Symbols 7 adı.
    public var symbolName: String {
        switch self {
        case .bash: "terminal"
        case .read: "doc.text"
        case .edit: "pencil.line"
        case .write: "square.and.pencil"
        case .search: "magnifyingglass"
        case .web: "globe"
        case .task: "person.2.wave.2"
        case .todo: "checklist"
        case .other: "wrench.and.screwdriver"
        }
    }
}

public enum Notice: Sendable, Hashable {
    case interrupted
    case error(String)
    case info(String)
}

public enum TranscriptItemKind: Sendable, Hashable {
    case user(String)
    case assistantText(String)
    case thinking(String, isStreaming: Bool)
    case redactedThinking
    case toolCall(ToolCall)
    case notice(Notice)
}

public struct TranscriptItem: Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: TranscriptItemKind
    /// Bu öğe hâlâ akıyor mu (UI imleç/animasyon için).
    public var isStreaming: Bool

    public init(id: String, kind: TranscriptItemKind, isStreaming: Bool = false) {
        self.id = id
        self.kind = kind
        self.isStreaming = isStreaming
    }
}
