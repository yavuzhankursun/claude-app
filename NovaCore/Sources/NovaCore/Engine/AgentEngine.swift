import Foundation
import os

/// Tüm canlı session'ların sahibi. Her session = bir `claude` alt süreci.
/// Actor: süreç tablosuna erişim serileştirilir; olay akışları doğrudan tüketiciye (SessionController) gider.
public actor AgentEngine {
    public struct SessionHandle: Sendable {
        public var id: UUID
        public var events: AsyncStream<ClaudeProcess.Event>
        public var pid: Int32
    }

    private var locator: CLILocator
    private var installation: CLILocator.Installation?
    private var processes: [UUID: ClaudeProcess] = [:]
    private let log = Logger(subsystem: "app.nova", category: "engine")

    public init(locator: CLILocator = CLILocator()) {
        self.locator = locator
    }

    public func setExecutableOverride(_ path: String?) {
        locator.overridePath = path
        installation = nil
    }

    public func resolveInstallation() async throws -> CLILocator.Installation {
        if let installation { return installation }
        let found = try await locator.locate()
        installation = found
        log.info("CLI found version=\(found.version ?? "?", privacy: .public)")
        return found
    }

    public func start(id: UUID, configuration: LaunchConfiguration) async throws -> SessionHandle {
        let install = try await resolveInstallation()
        if let existing = processes[id] { existing.terminate() }
        try FileManager.default.createDirectory(at: configuration.workingDirectory, withIntermediateDirectories: true)
        let process = try ClaudeProcess(executable: install.executable, configuration: configuration)
        processes[id] = process
        // Meta veri: mod ve izin modu. Prompt, yol ve dosya içeriği loglanmaz.
        log.info("session start mode=\(configuration.mode.rawValue, privacy: .public) perm=\(configuration.permissionMode.cliValue, privacy: .public) resume=\(configuration.resumeSessionId != nil, privacy: .public)")
        try process.send(.initialize(requestId: Self.requestId()))
        return SessionHandle(id: id, events: process.events, pid: process.processIdentifier)
    }

    public func isRunning(_ id: UUID) -> Bool {
        processes[id]?.isRunning ?? false
    }

    public func sendUserMessage(_ text: String, to id: UUID) throws {
        try process(id).send(.userText(text))
    }

    public func interrupt(_ id: UUID) throws {
        try process(id).send(.interrupt(requestId: Self.requestId()))
    }

    public func respond(to request: PermissionRequest, with decision: PermissionDecision, in id: UUID) throws {
        try process(id).send(.permissionDecision(requestId: request.requestId, decision: decision, request: request))
        log.info("permission tool=\(request.toolName, privacy: .public) decision=\(decision.logLabel, privacy: .public)")
    }

    public func setPermissionMode(_ mode: PermissionMode, in id: UUID) throws {
        try process(id).send(.setPermissionMode(requestId: Self.requestId(), mode: mode))
    }

    public func setModel(_ model: String?, in id: UUID) throws {
        try process(id).send(.setModel(requestId: Self.requestId(), model: model))
    }

    public func stop(_ id: UUID) {
        processes[id]?.terminate()
        processes[id] = nil
    }

    /// Süreç kendiliğinden çıktığında tablodan düşürülür.
    public func forget(_ id: UUID) {
        if processes[id]?.isRunning == false { processes[id] = nil }
    }

    public func stopAll() {
        for process in processes.values { process.terminate(grace: .milliseconds(500)) }
        processes.removeAll()
    }

    private func process(_ id: UUID) throws -> ClaudeProcess {
        guard let p = processes[id], p.isRunning else { throw ClaudeProcess.ProcessError.notRunning }
        return p
    }

    private static func requestId() -> String { "nova-" + UUID().uuidString.lowercased() }
}

extension PermissionDecision {
    var logLabel: String {
        switch self {
        case .allowOnce: "allow_once"
        case .allowForSession: "allow_session"
        case .deny: "deny"
        }
    }
}
