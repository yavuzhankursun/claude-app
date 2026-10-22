import Foundation
import MonsterCore
import SwiftData

/// Monster'ın session meta verisi (SwiftData). Transcript'in kendisi CLI'ın `~/.claude/projects` JSONL'ında kalır;
/// burada yalnızca başlık, mod, klasör ve tercihler tutulur (docs/adr/0002-persistence.md).
@Model
final class SessionRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var modeRaw: String
    /// Kod modunda proje klasörü; sohbet modunda nil.
    var projectPath: String?
    /// CLI'ın çalıştığı dizin (kod modunda = projectPath, sohbette Monster'ın boş dizini).
    var workingDirectoryPath: String
    var model: String?
    var effortRaw: String?
    var permissionModeRaw: String
    /// CLI session id'si; `--session-id` ile biz belirleriz ya da terminal session'ından içe aktarılır.
    var cliSessionId: String
    var createdAt: Date
    var lastActiveAt: Date
    var isImportedFromTerminal: Bool

    init(id: UUID = UUID(), title: String, mode: SessionMode, projectPath: String?, workingDirectoryPath: String,
         model: String?, effort: Effort?, permissionMode: PermissionMode, cliSessionId: String,
         isImportedFromTerminal: Bool = false) {
        self.id = id
        self.title = title
        self.modeRaw = mode.rawValue
        self.projectPath = projectPath
        self.workingDirectoryPath = workingDirectoryPath
        self.model = model
        self.effortRaw = effort?.rawValue
        self.permissionModeRaw = permissionMode.rawValue
        self.cliSessionId = cliSessionId
        self.createdAt = .now
        self.lastActiveAt = .now
        self.isImportedFromTerminal = isImportedFromTerminal
    }

    var mode: SessionMode {
        get { SessionMode(rawValue: modeRaw) ?? .code }
        set { modeRaw = newValue.rawValue }
    }

    var effort: Effort? {
        get { effortRaw.flatMap(Effort.init(rawValue:)) }
        set { effortRaw = newValue?.rawValue }
    }

    var permissionMode: PermissionMode {
        get { PermissionMode(rawValue: permissionModeRaw) ?? .ask }
        set { permissionModeRaw = newValue.rawValue }
    }

    var workingDirectory: URL { URL(filePath: workingDirectoryPath, directoryHint: .isDirectory) }

    var groupKey: String { projectPath ?? "" }
}
