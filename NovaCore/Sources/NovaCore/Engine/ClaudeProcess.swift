import Foundation
import Synchronization

/// Tek bir `claude -p` alt süreci. stdout NDJSON → `InboundMessage` akışı; stdin'e `OutboundMessage` yazar.
/// Argümanlar `Process.arguments` ile verilir — shell yoktur, kullanıcı metni asla komut satırına girmez
/// (kullanıcı mesajları stdin üzerinden JSON olarak gider).
// `@unchecked`: `Process`/`FileHandle` Foundation tipleri; değişken durum yalnızca `Mutex` arkasında.
public final class ClaudeProcess: @unchecked Sendable {
    public enum Event: Sendable {
        case message(InboundMessage)
        /// Çözülemeyen satır; içerik loglanmaz, sadece boyutu raporlanır.
        case malformedLine(byteCount: Int)
        case exited(status: Int32, reason: Process.TerminationReason, stderrTail: String)
    }

    public enum ProcessError: Error, LocalizedError {
        case notRunning
        case launchFailed(String)

        public var errorDescription: String? {
            switch self {
            case .notRunning: String(localized: "Claude süreci çalışmıyor.")
            case .launchFailed(let why): String(localized: "Claude başlatılamadı: \(why)")
            }
        }
    }

    public let events: AsyncStream<Event>
    public let launchedAt: Date

    private let process: Process
    private let stdinHandle: FileHandle
    private let continuation: AsyncStream<Event>.Continuation
    private let splitter = Mutex(NDJSONLineSplitter())
    private let stderrTail = Mutex(Data())
    private let writeLock = Mutex(())
    private let firstOutputAt = Mutex<Date?>(nil)

    private static let stderrTailLimit = 8 * 1024

    public init(executable: URL, configuration: LaunchConfiguration) throws {
        Self.ignoreSigpipeOnce()

        let process = Process()
        process.executableURL = executable
        process.arguments = configuration.arguments
        process.currentDirectoryURL = configuration.workingDirectory
        process.environment = CLILocator.augmentedEnvironment(for: executable)

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        // Ölçüm/backpressure: `.bufferingNewest` kullanılmaz; transcript kaybı kabul edilemez.
        let (stream, continuation) = AsyncStream<Event>.makeStream(bufferingPolicy: .unbounded)
        self.events = stream
        self.continuation = continuation
        self.process = process
        self.stdinHandle = stdin.fileHandleForWriting
        self.launchedAt = Date()

        let outReader = stdout.fileHandleForReading
        let errReader = stderr.fileHandleForReading

        outReader.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self.firstOutputAt.withLock { if $0 == nil { $0 = Date() } }
            let lines = self.splitter.withLock { $0.append(chunk) }
            for line in lines { self.emit(line: line) }
        }
        errReader.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self.stderrTail.withLock { tail in
                tail.append(chunk)
                if tail.count > Self.stderrTailLimit { tail = Data(tail.suffix(Self.stderrTailLimit)) }
            }
        }
        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            // Kalan çıktıyı boşalt, sonra akışı kapat.
            outReader.readabilityHandler = nil
            errReader.readabilityHandler = nil
            let rest = outReader.readDataToEndOfFile()
            var lines = self.splitter.withLock { $0.append(rest) }
            if let last = self.splitter.withLock({ $0.finish() }) { lines.append(last) }
            for line in lines { self.emit(line: line) }
            let tail = self.stderrTail.withLock { String(decoding: $0, as: UTF8.self) }
            self.continuation.yield(.exited(status: proc.terminationStatus, reason: proc.terminationReason, stderrTail: tail))
            self.continuation.finish()
        }

        do {
            try process.run()
        } catch {
            continuation.finish()
            throw ProcessError.launchFailed(error.localizedDescription)
        }
    }

    deinit {
        if process.isRunning { process.terminate() }
    }

    public var isRunning: Bool { process.isRunning }
    public var processIdentifier: Int32 { process.processIdentifier }
    /// Süreç başlatıldıktan sonra stdout'a ilk baytın gelme süresi (spawn gecikmesi ölçümü).
    public var timeToFirstOutput: TimeInterval? {
        firstOutputAt.withLock { $0?.timeIntervalSince(launchedAt) }
    }

    public func send(_ message: OutboundMessage) throws {
        guard process.isRunning else { throw ProcessError.notRunning }
        let data = message.encodedLine()
        try writeLock.withLock { _ in try stdinHandle.write(contentsOf: data) }
    }

    /// stdin'i kapatır; CLI mevcut turu bitirip çıkar.
    public func closeInput() {
        writeLock.withLock { _ in try? stdinHandle.close() }
    }

    /// Önce SIGTERM, `grace` sonra hâlâ yaşıyorsa SIGKILL.
    public func terminate(grace: Duration = .seconds(2)) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        process.terminate()
        Task.detached { [weak self] in
            try? await Task.sleep(for: grace)
            if self?.isRunning == true { kill(pid, SIGKILL) }
        }
    }

    private func emit(line: Data) {
        if let message = InboundMessage.decode(line: line) {
            continuation.yield(.message(message))
        } else {
            continuation.yield(.malformedLine(byteCount: line.count))
        }
    }

    private static let sigpipeIgnored: Void = {
        // Ölmüş bir sürecin stdin'ine yazmak SIGPIPE ile uygulamayı düşürmesin; write() hata döndürsün.
        signal(SIGPIPE, SIG_IGN)
    }()

    private static func ignoreSigpipeOnce() { _ = sigpipeIgnored }
}
