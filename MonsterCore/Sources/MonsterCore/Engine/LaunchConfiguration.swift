import Foundation

public enum SessionMode: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    /// Proje klasörü yok; boş bir çalışma dizininde salt-okunur araçlarla sohbet.
    case chat
    /// Seçilen proje klasöründe tam Claude Code.
    case code

    public var id: String { rawValue }
}

public enum Effort: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case low, medium, high, xhigh, max
    public var id: String { rawValue }
}

/// Bir `claude` alt sürecini başlatmak için gereken her şey. Argüman listesi üretir; shell kullanılmaz.
public struct LaunchConfiguration: Sendable, Hashable {
    public var mode: SessionMode
    public var workingDirectory: URL
    public var model: String?
    public var effort: Effort?
    public var permissionMode: PermissionMode
    /// Devam edilecek CLI session id'si (`--resume`).
    public var resumeSessionId: String?
    /// Yeni session için önceden belirlenen id (`--session-id`); UI kaydı ile CLI'ı ilk turdan eşler.
    public var newSessionId: String?
    public var additionalDirectories: [URL]

    /// Sohbet modunda izin verilen araçlar: dosya yazma ve shell yok.
    public static let chatTools = ["Read", "Glob", "Grep", "WebSearch", "WebFetch"]
    public static let chatDisallowedTools = ["Bash", "Edit", "Write", "NotebookEdit", "PowerShell"]

    public init(mode: SessionMode, workingDirectory: URL, model: String? = nil, effort: Effort? = nil,
                permissionMode: PermissionMode = .ask, resumeSessionId: String? = nil,
                newSessionId: String? = nil, additionalDirectories: [URL] = []) {
        self.mode = mode
        self.workingDirectory = workingDirectory
        self.model = model
        self.effort = effort
        self.permissionMode = permissionMode
        self.resumeSessionId = resumeSessionId
        self.newSessionId = newSessionId
        self.additionalDirectories = additionalDirectories
    }

    public var arguments: [String] {
        var args = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            // İzin istekleri stdout'ta `control_request/can_use_tool` olarak gelir; Monster cevaplar.
            "--permission-prompts", "host",
            "--permission-prompt-tool", "stdio",
        ]
        if let model, !model.isEmpty { args += ["--model", model] }
        if let effort { args += ["--effort", effort.rawValue] }

        switch mode {
        case .chat:
            // Sohbet modu her zaman "Ask"; yazma/shell araçları hiç yüklenmez.
            args += ["--permission-mode", PermissionMode.ask.cliValue]
            args += ["--tools", Self.chatTools.joined(separator: ",")]
            args += ["--disallowed-tools", Self.chatDisallowedTools.joined(separator: ",")]
        case .code:
            args += ["--permission-mode", permissionMode.cliValue]
            // Session ortasında "Full access"e geçilebilmesi için seçenek açılır ama varsayılan değildir.
            // UI bu geçişi kırmızı rozet + onay ile kapılar (docs/THREAT_MODEL.md, T-4).
            args += ["--allow-dangerously-skip-permissions"]
            for dir in additionalDirectories { args += ["--add-dir", dir.path] }
        }

        if let resumeSessionId {
            args += ["--resume", resumeSessionId]
        } else if let newSessionId {
            args += ["--session-id", newSessionId]
        }
        return args
    }
}
