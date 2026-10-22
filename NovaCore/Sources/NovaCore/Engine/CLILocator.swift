import Foundation

/// Kurulu `claude` çalıştırılabilirini bulur. GUI uygulamaları kullanıcının shell PATH'ini miras almaz,
/// bu yüzden önce bilinen kurulum yerleri, sonra sabit bir login-shell sorgusu denenir.
public struct CLILocator: Sendable {
    public struct Installation: Sendable, Hashable {
        public var executable: URL
        public var version: String?
    }

    public enum LocateError: Error, LocalizedError {
        case notFound
        public var errorDescription: String? {
            String(localized: "Claude Code CLI bulunamadı. `claude` kurulu ve en az bir kez giriş yapılmış olmalı.")
        }
    }

    /// Nova'nın test edildiği CLI sürümü. Farklı majör/minör sürümde UI uyarı gösterir (parser yine toleranslıdır).
    public static let testedVersion = "2.1.308"

    public var overridePath: String?
    public var home: URL

    public init(overridePath: String? = nil, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.overridePath = overridePath
        self.home = home
    }

    public var candidatePaths: [String] {
        var paths: [String] = []
        if let overridePath, !overridePath.isEmpty { paths.append((overridePath as NSString).expandingTildeInPath) }
        paths += [
            home.appending(path: ".local/bin/claude").path,
            home.appending(path: ".claude/local/claude").path,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            home.appending(path: ".npm-global/bin/claude").path,
            home.appending(path: ".bun/bin/claude").path,
        ]
        return paths
    }

    public func locate() async throws -> Installation {
        let fm = FileManager.default
        if let found = candidatePaths.first(where: { fm.isExecutableFile(atPath: $0) }) {
            let url = URL(filePath: found)
            return Installation(executable: url, version: await Self.version(of: url))
        }
        if let viaShell = await Self.lookupViaLoginShell(), fm.isExecutableFile(atPath: viaShell) {
            let url = URL(filePath: viaShell)
            return Installation(executable: url, version: await Self.version(of: url))
        }
        throw LocateError.notFound
    }

    /// Sabit komut; kullanıcı girdisi içermez.
    static func lookupViaLoginShell() async -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let output = await runCapturing(URL(filePath: shell), ["-l", "-c", "command -v claude"])
        return output?.split(separator: "\n").last.map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    static func version(of executable: URL) async -> String? {
        guard let output = await runCapturing(executable, ["--version"]) else { return nil }
        // "2.1.308 (Claude Code)"
        return output.split(separator: " ").first.map(String.init)
    }

    /// Ek PATH girdileri: npm tabanlı kurulumlarda `#!/usr/bin/env node` için node bulunabilmeli.
    public static func augmentedEnvironment(for executable: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        let current = env["PATH"].map { $0.split(separator: ":").map(String.init) } ?? []
        env["PATH"] = (extra + current).reduce(into: [String]()) { acc, p in if !acc.contains(p) { acc.append(p) } }
            .joined(separator: ":")
        // Nova içinden başlatılan CLI'ın başka bir Claude Code oturumunun çocuğu sanılmaması için.
        env.removeValue(forKey: "CLAUDECODE")
        return env
    }

    private static func runCapturing(_ executable: URL, _ arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = augmentedEnvironment(for: executable)
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            let reader = pipe.fileHandleForReading
            process.terminationHandler = { proc in
                // Çıktı küçük (sürüm / tek yol); pipe tamponunu doldurmaz.
                let data = reader.readDataToEndOfFile()
                let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: proc.terminationStatus == 0 && !text.isEmpty ? text : nil)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }
            // Login shell (ör. bozuk bir .zshrc) takılırsa 5 sn sonra sonlandırılır; terminationHandler nil döndürür.
            // PID değil Process üzerinden: süreç çoktan bittiyse yeniden kullanılmış bir PID'ye sinyal gitmez.
            let box = ProcessBox(process)
            Task.detached {
                try? await Task.sleep(for: .seconds(5))
                if box.process.isRunning { box.process.terminate() }
            }
        }
    }

    public static func isTested(version: String?) -> Bool {
        guard let version else { return false }
        let a = version.split(separator: ".").prefix(2)
        let b = testedVersion.split(separator: ".").prefix(2)
        return a == b
    }
}

/// `Process` Foundation'da Sendable işaretli değil; yalnızca `isRunning`/`terminate` için taşınır.
private final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}
