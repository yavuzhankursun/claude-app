import Foundation
import MonsterCore
import Observation
import SwiftData

/// Uygulama genelindeki durum: CLI kurulumu, session kayıtları, terminal geçmişi ve canlı controller'lar.
@Observable
final class AppModel {
    enum CLIStatus: Equatable {
        case checking
        case found(version: String?, tested: Bool)
        case missing
    }

    let engine = AgentEngine()
    let history = HistoryIndexer()
    let context: ModelContext

    private(set) var records: [SessionRecord] = []
    /// Monster'a henüz aktarılmamış terminal session'ları.
    private(set) var terminalEntries: [HistoryEntry] = []
    private(set) var cliStatus: CLIStatus = .checking
    private(set) var isRefreshingHistory = false
    /// Controller'ı oluşturulmuş session'lar (kenar çubuğundaki canlı gösterge bunu gözler).
    private(set) var controllerIds: Set<UUID> = []

    @ObservationIgnored private var controllers: [UUID: SessionController] = [:]
    @ObservationIgnored private var historyCache: [URL: HistoryEntry] = [:]

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Başlangıç

    func bootstrap() async {
        loadRecords()
        async let cli: Void = checkCLI()
        async let hist: Void = refreshHistory()
        _ = await (cli, hist)
    }

    func checkCLI() async {
        cliStatus = .checking
        await engine.setExecutableOverride(UserDefaults.standard.string(forKey: SettingsKeys.cliPath))
        do {
            let install = try await engine.resolveInstallation()
            cliStatus = .found(version: install.version, tested: CLILocator.isTested(version: install.version))
        } catch {
            cliStatus = .missing
        }
    }

    func refreshHistory() async {
        guard !isRefreshingHistory else { return }
        isRefreshingHistory = true
        defer { isRefreshingHistory = false }
        let indexer = history
        let cache = historyCache
        let entries = await Task.detached(priority: .utility) { indexer.scan(cache: cache) }.value
        historyCache = Dictionary(entries.map { ($0.fileURL, $0) }, uniquingKeysWith: { a, _ in a })
        let imported = Set(records.map(\.cliSessionId))
        terminalEntries = entries.filter { !imported.contains($0.sessionId) }
    }

    private func loadRecords() {
        let descriptor = FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.lastActiveAt, order: .reverse)])
        records = (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Session'lar

    func record(id: UUID) -> SessionRecord? {
        records.first { $0.id == id }
    }

    func controller(for record: SessionRecord) -> SessionController {
        if let existing = controllers[record.id] { return existing }
        let controller = SessionController(record: record, engine: engine, history: history)
        controllers[record.id] = controller
        // Görünüm gövdesi sırasında gözlenen durumu değiştirmemek için bir sonraki tura ertelenir.
        let id = record.id
        Task { self.controllerIds.insert(id) }
        return controller
    }

    func liveController(id: UUID) -> SessionController? {
        controllerIds.contains(id) ? controllers[id] : nil
    }

    @discardableResult
    func createSession(mode: SessionMode, folder: URL?, model: String?, effort: Effort?,
                       permissionMode: PermissionMode) throws -> SessionRecord {
        let id = UUID()
        let workingDirectory: URL
        switch mode {
        case .chat:
            workingDirectory = try Self.chatDirectory(for: id)
        case .code:
            guard let folder else { throw NewSessionError.folderRequired }
            workingDirectory = folder
        }
        let record = SessionRecord(
            id: id, title: SessionTitles.placeholder, mode: mode,
            projectPath: mode == .code ? folder?.path : nil,
            workingDirectoryPath: workingDirectory.path,
            model: model, effort: effort,
            permissionMode: mode == .chat ? .ask : permissionMode,
            cliSessionId: UUID().uuidString.lowercased()
        )
        context.insert(record)
        try? context.save()
        records.insert(record, at: 0)
        return record
    }

    /// Terminalde başlatılmış bir session'ı Monster'a alır; ilk mesajda `--resume` ile devam eder.
    func importTerminalSession(_ entry: HistoryEntry) -> SessionRecord {
        if let existing = records.first(where: { $0.cliSessionId == entry.sessionId }) { return existing }
        let path = entry.projectPath ?? FileManager.default.homeDirectoryForCurrentUser.path
        let record = SessionRecord(
            title: entry.title, mode: .code, projectPath: entry.projectPath, workingDirectoryPath: path,
            model: nil, effort: nil,
            permissionMode: PermissionMode(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.defaultPermission) ?? "") ?? .ask,
            cliSessionId: entry.sessionId, isImportedFromTerminal: true
        )
        record.lastActiveAt = entry.lastModified
        context.insert(record)
        try? context.save()
        records.insert(record, at: 0)
        terminalEntries.removeAll { $0.sessionId == entry.sessionId }
        return record
    }

    func delete(_ record: SessionRecord) async {
        if let controller = controllers.removeValue(forKey: record.id) { await controller.stopProcess() }
        controllerIds.remove(record.id)
        records.removeAll { $0.id == record.id }
        context.delete(record)
        try? context.save()
        // CLI transcript dosyasına dokunulmaz (salt-okunur ilke); terminal listesinde yeniden görünebilir.
        await refreshHistory()
    }

    func save() {
        try? context.save()
    }

    func shutdown() async {
        save()
        await engine.stopAll()
    }

    // MARK: - Kenar çubuğu

    struct Section: Identifiable {
        var id: String
        var title: String
        var subtitle: String?
        var records: [SessionRecord]
        var terminal: [HistoryEntry]
    }

    func sections(matching query: String) -> [Section] {
        let q = query.trimmingCharacters(in: .whitespaces)
        func matches(_ s: String?) -> Bool { q.isEmpty || (s?.localizedStandardContains(q) ?? false) }

        var groups: [String: Section] = [:]
        var order: [String] = []
        func bucket(_ key: String, title: String, subtitle: String?) -> String {
            if groups[key] == nil {
                groups[key] = Section(id: key, title: title, subtitle: subtitle, records: [], terminal: [])
                order.append(key)
            }
            return key
        }

        for record in records where matches(record.title) || matches(record.projectPath) {
            let key: String
            if let project = record.projectPath {
                key = bucket(project, title: URL(filePath: project).lastPathComponent, subtitle: Self.abbreviate(project))
            } else {
                key = bucket("chat", title: String(localized: "Sohbetler"), subtitle: nil)
            }
            groups[key]?.records.append(record)
        }
        for entry in terminalEntries where matches(entry.title) || matches(entry.firstPrompt) || matches(entry.projectPath) {
            let project = entry.projectPath ?? "?"
            let key = bucket(project, title: entry.projectName, subtitle: Self.abbreviate(project))
            groups[key]?.terminal.append(entry)
        }
        return order.compactMap { groups[$0] }
    }

    static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    static func chatDirectory(for id: UUID) throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let dir = base.appending(path: "Monster/Chats/\(id.uuidString.lowercased())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

enum NewSessionError: LocalizedError {
    case folderRequired
    var errorDescription: String? { String(localized: "Kod modu için bir proje klasörü seçin.") }
}

enum SettingsKeys {
    static let cliPath = "cliPath"
    static let defaultModel = "defaultModel"
    static let defaultEffort = "defaultEffort"
    static let defaultPermission = "defaultPermission"
    static let fullAccessAcknowledged = "fullAccessAcknowledged"
    static let prewarm = "prewarmProcesses"
    static let appearance = "appearance"
}

/// Pencere başına durum (çoklu pencere): seçim, sayfalar, palet.
@Observable
final class WindowState {
    var selection: SidebarSelection?
    var showNewSession = false
    var newSessionMode: SessionMode = .code
    var showPalette = false
    var sidebarQuery = ""
}

enum SidebarSelection: Hashable {
    case record(UUID)
    case terminal(String)
}
