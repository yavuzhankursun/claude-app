import Foundation

/// Composer'a sürükle-bırak, yapıştırma ya da dosya seçiciyle eklenen öğe. Kullanıcı açıkça seçtiği için proje kökü
/// sınırı yoktur (`@yol`dan farkı bu); boyut ve tür sınırları vardır.
public struct Attachment: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        /// API'ye görsel bloğu olarak gider. Tür uzantıdan değil dosyanın ilk baytlarından belirlenir.
        case image(mediaType: String)
        /// Metin dosyası: içerik satır içine konur.
        case text(content: String)
        /// Büyük/ikili dosya: yalnızca mutlak yolu yazılır; model gerekirse kendi aracıyla okur (izin sorar).
        case reference
    }

    public let id = UUID()
    public var name: String
    public var url: URL?
    public var kind: Kind
    /// Yalnızca görseller için ham bayt.
    public var data: Data

    public static let maxImageBytes = 5 * 1024 * 1024
    public static let maxAttachments = 10

    public init(name: String, url: URL?, kind: Kind, data: Data) {
        self.name = name
        self.url = url
        self.kind = kind
        self.data = data
    }

    public static func == (lhs: Attachment, rhs: Attachment) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public static func load(from url: URL) throws(AttachmentError) -> Attachment {
        // Kullanıcının açıkça seçtiği dosya: bağ önce bilerek çözülür, okuma yine bağ izlemeden ve sınırlı yapılır.
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        let name = url.lastPathComponent
        switch SafeFile.read(url, maxBytes: maxImageBytes) {
        case .notRegular:
            throw .notAFile(name)
        case .unreadable, .outsideRoot:
            throw .unreadable(name)
        case .tooLarge(let head, let size):
            if ImageSniffer.mediaType(of: head) != nil { throw .imageTooLarge(name, bytes: size) }
            return Attachment(name: name, url: url, kind: .reference, data: Data())
        case .data(let data):
            if let mediaType = ImageSniffer.mediaType(of: data.prefix(16)) {
                return Attachment(name: name, url: url, kind: .image(mediaType: mediaType), data: data)
            }
            if data.count <= MentionResolver.maxInlineBytes, let text = SafeFile.text(from: data) {
                return Attachment(name: name, url: url, kind: .text(content: text), data: Data())
            }
            return Attachment(name: name, url: url, kind: .reference, data: Data())
        }
    }

    /// Panodan gelen görsel (dosya yolu olmadan). PNG/JPEG/GIF/WebP değilse ya da sınırı aşarsa hata.
    public static func image(data: Data, name: String) throws(AttachmentError) -> Attachment {
        guard let mediaType = ImageSniffer.mediaType(of: data.prefix(16)) else { throw .unsupportedImage(name) }
        guard data.count <= maxImageBytes else { throw .imageTooLarge(name, bytes: data.count) }
        return Attachment(name: name, url: nil, kind: .image(mediaType: mediaType), data: data)
    }
}

public enum AttachmentError: Error, Sendable, Hashable, LocalizedError {
    case notAFile(String)
    case unreadable(String)
    case imageTooLarge(String, bytes: Int)
    case unsupportedImage(String)

    public var errorDescription: String? {
        switch self {
        case .notAFile(let name): "\(name) bir dosya değil."
        case .unreadable(let name): "\(name) okunamadı."
        case .imageTooLarge(let name, let bytes):
            "\(name) çok büyük (\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))); görsel sınırı 5 MB."
        case .unsupportedImage(let name): "\(name): yalnızca PNG, JPEG, GIF ve WebP görseller eklenebilir."
        }
    }
}

enum ImageSniffer {
    /// API'nin kabul ettiği görsel türleri, sihirli baytlarla.
    static func mediaType(of head: some DataProtocol) -> String? {
        let b = Array(head.prefix(12))
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "image/png" }
        if b.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if b.starts(with: Array("GIF87a".utf8)) || b.starts(with: Array("GIF89a".utf8)) { return "image/gif" }
        if b.count >= 12, b.starts(with: Array("RIFF".utf8)), Array(b[8..<12]) == Array("WEBP".utf8) { return "image/webp" }
        return nil
    }
}

/// Composer'dan giden kullanıcı mesajı: metin + çözülmüş `@yol`lar + ekler.
public struct UserMessage: Sendable, Hashable {
    public var text: String
    public var mentions: [ResolvedMention]
    public var attachments: [Attachment]

    public init(text: String, mentions: [ResolvedMention] = [], attachments: [Attachment] = []) {
        self.text = text
        self.mentions = mentions
        self.attachments = attachments
    }

    /// Ek yoksa düz metin (CLI'ın slash komutlarını tanıdığı biçim); varsa içerik blokları.
    var content: JSONValue {
        let mentionBlocks = mentions.compactMap(Self.block(for:))
        guard !mentionBlocks.isEmpty || !attachments.isEmpty else { return .string(text) }
        var blocks: [JSONValue] = [["type": "text", "text": .string(text)]]
        blocks += mentionBlocks
        for attachment in attachments {
            switch attachment.kind {
            case .image(let mediaType):
                blocks.append(["type": "image", "source": [
                    "type": "base64", "media_type": .string(mediaType), "data": .string(attachment.data.base64EncodedString()),
                ]])
            case .text(let content):
                blocks.append(["type": "text", "text": .string(Self.fileText(name: attachment.url?.path ?? attachment.name, content: content))])
            case .reference:
                let path = attachment.url?.path ?? attachment.name
                blocks.append(["type": "text", "text": .string(Self.attachedReferencePrefix + path)])
            }
        }
        return .array(blocks)
    }

    /// Ekranda kullanıcı balonunda gösterilen metin: ekler satır olarak.
    public var displayText: String {
        guard !attachments.isEmpty else { return text }
        let lines = attachments.map { attachment -> String in
            if case .image = attachment.kind { return "🖼 \(attachment.name)" }
            return "📎 \(attachment.name)"
        }
        return ([text] + lines).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func block(for mention: ResolvedMention) -> JSONValue? {
        switch mention {
        case .text(let path, let content): ["type": "text", "text": .string(fileText(name: path, content: content))]
        case .reference(let path): ["type": "text", "text": .string(Self.mentionedReferencePrefix + path)]
        case .rejected: nil
        }
    }

    static let attachedReferencePrefix = "Ekli dosya (içerik eklenmedi, gerekirse oku): "
    static let mentionedReferencePrefix = "Bahsedilen dosya (içerik eklenmedi, gerekirse oku): "

    /// Geçmişte (JSONL) Monster'ın eklediği blok ise kullanıcı balonundaki satırı (`📎 yol`); değilse `nil`.
    static func attachmentLine(forBlockText text: String) -> String? {
        for prefix in [attachedReferencePrefix, mentionedReferencePrefix] where text.hasPrefix(prefix) {
            return "📎 " + text.dropFirst(prefix.count)
        }
        let opening = "<file path=\""
        guard text.hasPrefix(opening), let end = text.range(of: "\" id=") else { return nil }
        let path = text[text.index(text.startIndex, offsetBy: opening.count)..<end.lowerBound]
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
        return "📎 " + path
    }

    /// İçerik, içinde geçmeyen rastgele bir sınırlayıcıyla sarılır: dosyadaki `</file>` etiketi kapatıp sonrasını kullanıcı
    /// metni gibi gösteremez (güvenlik incelemesi #5). Yoldaki `\`, `"` ve satır sonları kaçırılır.
    private static func fileText(name: String, content: String) -> String {
        var nonce: String
        repeat { nonce = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)).lowercased() }
        while content.contains(nonce)
        let path = name.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        return "<file path=\"\(path)\" id=\(nonce)>\n\(content)\n</file id=\(nonce)>"
    }
}
