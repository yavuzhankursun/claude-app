import Foundation

/// `@yol` bahsetmeleri. CLI stream-json modunda `@dosya`yı kendisi açmıyor (spike 2026-10-22: model dosyayı Bash ile
/// okumaya gitti); bu yüzden Monster bahsedilen dosyayı mesaja ek metin bloğu olarak koyar (`MentionResolver`).
/// Yoldaki boşluk `\ ` ile kaçırılır.
public enum MentionQuery {
    /// Taslağın son sözcüğü `@` ile başlıyorsa (ve öncesi boşluk/satır başıysa) yazılmakta olan sorgu; değilse `nil`.
    public static func active(in draft: String) -> String? {
        guard let token = lastToken(of: draft), token.hasPrefix("@") else { return nil }
        return unescape(String(token.dropFirst()))
    }

    /// Yazılmakta olan `@sorgu`yu seçilen yolla değiştirir ve bir boşluk ekler.
    public static func replacingActive(in draft: String, with path: String) -> String {
        guard let token = lastToken(of: draft), token.hasPrefix("@") else { return draft }
        return String(draft.dropLast(token.count)) + "@" + escape(path) + " "
    }

    /// Metindeki tüm `@yol`lar (kaçış çözülmüş, sondaki noktalama atılmış). E-posta gibi sözcük içi `@` sayılmaz.
    public static func mentions(in text: String) -> [String] {
        var result: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            let atWordStart = index == text.startIndex || text[text.index(before: index)].isWhitespace
            guard text[index] == "@", atWordStart else { index = text.index(after: index); continue }
            var end = text.index(after: index)
            while end < text.endIndex {
                if text[end] == "\\", text.index(after: end) < text.endIndex {
                    end = text.index(end, offsetBy: 2)
                } else if text[end].isWhitespace {
                    break
                } else {
                    end = text.index(after: end)
                }
            }
            var path = unescape(String(text[text.index(after: index)..<end]))
            while let last = path.last, ",.;:!?)]}\"'".contains(last) { path.removeLast() }
            if !path.isEmpty { result.append(path) }
            index = end
        }
        return result
    }

    static func escape(_ path: String) -> String { path.replacingOccurrences(of: " ", with: "\\ ") }
    static func unescape(_ path: String) -> String { path.replacingOccurrences(of: "\\ ", with: " ") }

    /// Kaçırılmış boşluğu (`\ `) sözcük ayırıcı saymayan son sözcük.
    private static func lastToken(of draft: String) -> Substring? {
        guard let last = draft.last, !last.isWhitespace else { return nil }
        var start = draft.endIndex
        while start > draft.startIndex {
            let previous = draft.index(before: start)
            if draft[previous].isWhitespace {
                let escaped = previous > draft.startIndex && draft[draft.index(before: previous)] == "\\"
                if !escaped { break }
            }
            start = previous
        }
        return draft[start...]
    }
}

/// Proje dosyalarının göreli yol listesi ve bulanık arama. Ağır/üretilmiş dizinler atlanır.
public struct FileIndex: Sendable {
    public let paths: [String]

    public static let skippedDirectories: Set<String> = [
        ".git", ".hg", ".svn", "node_modules", ".build", "build", "DerivedData", "Pods", ".swiftpm",
        "dist", ".next", "target", "__pycache__", ".venv", "venv", ".gradle", ".idea", "Carthage",
    ]
    public static let maxFiles = 20_000

    public init(paths: [String]) { self.paths = paths }

    public static func build(root: URL, limit: Int = maxFiles) -> FileIndex {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else {
            return FileIndex(paths: [])
        }
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var paths: [String] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if skippedDirectories.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true, values?.isSymbolicLink != true, url.lastPathComponent != ".DS_Store" else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { continue }
            paths.append(String(path.dropFirst(prefix.count)))
            if paths.count >= limit { break }
        }
        return FileIndex(paths: paths.sorted())
    }

    /// Alt dizi (subsequence) eşleşmesi; dosya adında eşleşme ve ardışık karakterler öne çıkar, kısa yol öne.
    public func search(_ query: String, limit: Int = 8) -> [String] {
        let q = query.lowercased().filter { !$0.isWhitespace }
        guard !q.isEmpty else { return Array(paths.prefix(limit)) }
        let scored = paths.compactMap { path -> (String, Int)? in
            let lower = path.lowercased()
            let name = (lower as NSString).lastPathComponent
            guard var score = Self.subsequenceScore(q, in: lower) else { return nil }
            if name.hasPrefix(q) { score += 200 } else if name.contains(q) { score += 120 }
            else if let nameScore = Self.subsequenceScore(q, in: name) { score += 40 + nameScore }
            return (path, score - path.count / 4)
        }
        return Array(scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }.prefix(limit).map(\.0))
    }

    private static func subsequenceScore(_ query: String, in text: String) -> Int? {
        var score = 0
        var streak = 0
        var position = text.startIndex
        for character in query {
            guard let found = text[position...].firstIndex(of: character) else { return nil }
            streak = found == position ? streak + 1 : 0
            score += 1 + streak * 3
            position = text.index(after: found)
        }
        return score
    }
}

/// Mesajdaki `@yol`ların güvenli çözümü.
public enum ResolvedMention: Sendable, Hashable {
    /// Satır içine konacak metin dosyası.
    case text(path: String, content: String)
    /// Büyük ya da ikili dosya: içerik eklenmez, model gerekirse kendi aracıyla (izin sorarak) okur.
    case reference(path: String)
    /// Proje kökü dışına çıkan yol; hiçbir şey eklenmez.
    case rejected(path: String)
}

public enum MentionResolver {
    public static let maxInlineBytes = 256 * 1024
    public static let maxMentions = 20

    /// Güvenlik: yol köke göre çözülür, sembolik bağlar açılır ve sonuç kökün içinde değilse reddedilir
    /// (`..`, mutlak yol, dışarıyı gösteren bağ). Var olmayan yollar sessizce atlanır (metin olarak kalır).
    public static func resolve(text: String, root: URL) -> [ResolvedMention] {
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
        var seen: Set<String> = []
        var result: [ResolvedMention] = []
        for mention in MentionQuery.mentions(in: text).prefix(maxMentions) where seen.insert(mention).inserted {
            let candidate = mention.hasPrefix("/") ? URL(filePath: mention) : base.appending(path: mention)
            let real = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard real.path.hasPrefix(prefix) else {
                if FileManager.default.fileExists(atPath: candidate.path) { result.append(.rejected(path: mention)) }
                continue
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: real.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            let relative = String(real.path.dropFirst(prefix.count))
            // Kontrol ile okuma arası değişime karşı okuma da kök önekiyle ve bağ izlemeden yapılır (`SafeFile`).
            switch SafeFile.read(real, maxBytes: maxInlineBytes, within: base) {
            case .data(let data):
                if let content = SafeFile.text(from: data) {
                    result.append(.text(path: relative, content: content))
                } else {
                    result.append(.reference(path: relative))
                }
            case .tooLarge:
                result.append(.reference(path: relative))
            case .outsideRoot:
                result.append(.rejected(path: mention))
            case .notRegular, .unreadable:
                continue
            }
        }
        return result
    }

    /// Boyut sınırı içinde, NUL baytı olmayan geçerli UTF-8 ise metin (sınırlı, bağ izlemeyen okuma).
    static func inlineText(at url: URL) -> String? {
        guard case .data(let data) = SafeFile.read(url, maxBytes: maxInlineBytes) else { return nil }
        return SafeFile.text(from: data)
    }
}
