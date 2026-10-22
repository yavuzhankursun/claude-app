import Foundation

/// `~/.claude/projects/<kodlanmış-yol>/<session-id>.jsonl` dosyalarının özeti.
/// Terminalde başlatılan session'lar da burada görünür ve `--resume` ile devam ettirilebilir.
public struct HistoryEntry: Sendable, Hashable, Identifiable {
    public var id: String { sessionId }
    public var sessionId: String
    public var fileURL: URL
    public var projectPath: String?
    public var title: String
    public var firstPrompt: String?
    public var gitBranch: String?
    public var cliVersion: String?
    public var lastModified: Date
    public var fileSize: Int

    public var projectName: String {
        guard let projectPath else { return String(localized: "Bilinmeyen proje") }
        return URL(filePath: projectPath).lastPathComponent
    }
}

/// Dosyaları salt-okunur tarar. Büyük transcript'lerde yalnızca baştan ve sondan birer pencere okunur.
public struct HistoryIndexer: Sendable {
    public var root: URL
    public var headBytes = 128 * 1024
    public var tailBytes = 64 * 1024

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects")) {
        self.root = root
    }

    /// Bir CLI session id'sinin transcript dosyası (varsa). `--resume` mi `--session-id` mi kullanılacağına karar verir.
    public func fileURL(forSession sessionId: String) -> URL? {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return nil }
        return projects.lazy
            .map { $0.appending(path: "\(sessionId).jsonl") }
            .first { fm.fileExists(atPath: $0.path) }
    }

    public func scan(cache: [URL: HistoryEntry] = [:]) -> [HistoryEntry] {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                          options: [.skipsHiddenFiles]) else { return [] }
        var entries: [HistoryEntry] = []
        for dir in projects {
            guard let files = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])
            else { continue }
            for file in files where file.pathExtension == "jsonl" {
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let modified = values?.contentModificationDate ?? .distantPast
                let size = values?.fileSize ?? 0
                if let cached = cache[file], cached.lastModified == modified, cached.fileSize == size {
                    entries.append(cached)
                } else if let entry = summarize(file: file, modified: modified, size: size) {
                    entries.append(entry)
                }
            }
        }
        return entries.sorted { $0.lastModified > $1.lastModified }
    }

    func summarize(file: URL, modified: Date, size: Int) -> HistoryEntry? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        let head = (try? handle.read(upToCount: headBytes)) ?? Data()
        var tail = Data()
        if size > headBytes {
            let offset = UInt64(max(headBytes, size - tailBytes))
            try? handle.seek(toOffset: offset)
            tail = (try? handle.readToEnd()) ?? Data()
        }

        var cwd: String?
        var branch: String?
        var version: String?
        var firstPrompt: String?
        var title: String?
        var sawConversation = false

        func scanLines(_ data: Data, dropFirstPartial: Bool) {
            var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
            if dropFirstPartial, !lines.isEmpty { lines.removeFirst() }
            for line in lines {
                guard let json = try? JSONValue.parse(Data(line)) else { continue }
                cwd = cwd ?? json["cwd"]?.stringValue
                branch = json["gitBranch"]?.stringValue ?? branch
                version = json["version"]?.stringValue ?? version
                if let t = Self.titleCandidate(json) { title = t }
                let type = json["type"]?.stringValue
                if type == "user" || type == "assistant" { sawConversation = true }
                if firstPrompt == nil, type == "user", json["isSidechain"]?.boolValue != true, json["isMeta"]?.boolValue != true {
                    firstPrompt = Self.promptText(json["message"]?["content"])
                }
            }
        }
        scanLines(head, dropFirstPartial: false)
        if !tail.isEmpty { scanLines(tail, dropFirstPartial: true) }

        guard sawConversation else { return nil }
        let sessionId = file.deletingPathExtension().lastPathComponent
        let fallbackTitle = firstPrompt.map { Self.truncate($0, to: 80) } ?? String(localized: "Adsız session")
        return HistoryEntry(sessionId: sessionId, fileURL: file, projectPath: cwd, title: title ?? fallbackTitle,
                            firstPrompt: firstPrompt, gitBranch: branch, cliVersion: version,
                            lastModified: modified, fileSize: size)
    }

    /// CLI sürümleri farklı başlık satırları yazar; hepsi toleranslı okunur.
    static func titleCandidate(_ json: JSONValue) -> String? {
        switch json["type"]?.stringValue {
        case "custom-title": return json["customTitle"]?.stringValue ?? json["title"]?.stringValue
        case "ai-title": return json["aiTitle"]?.stringValue ?? json["title"]?.stringValue
        case "summary": return json["summary"]?.stringValue
        default: return nil
        }
    }

    static func promptText(_ content: JSONValue?) -> String? {
        let text: String?
        switch content {
        case .string(let s)?: text = s
        case .array(let blocks)?:
            text = blocks.first { $0["type"]?.stringValue == "text" }?["text"]?.stringValue
        default: text = nil
        }
        guard let text, !text.isEmpty, !TranscriptState.isSyntheticUserText(text) else { return nil }
        return text
    }

    static func truncate(_ s: String, to limit: Int) -> String {
        let oneLine = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return oneLine.count <= limit ? oneLine : String(oneLine.prefix(limit - 1)) + "…"
    }
}

/// Bir geçmiş dosyasını transcript durumuna dönüştürür (salt-okunur).
public enum HistoryLoader {
    public static func load(_ url: URL) throws -> TranscriptState {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return load(data: data)
    }

    public static func load(data: Data) -> TranscriptState {
        var state = TranscriptState()
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let json = try? JSONValue.parse(Data(line)) else { continue }
            // Alt ajan dalları ve meta kayıtlar ana transcript'te gösterilmez.
            if json["isSidechain"]?.boolValue == true || json["isMeta"]?.boolValue == true { continue }
            switch json["type"]?.stringValue {
            case "user", "assistant":
                state.apply(InboundMessage(json: json))
            default:
                continue
            }
        }
        state.markProcessExited(error: nil)
        return state
    }
}
