import Foundation

/// Asistan metnini blok düzeyinde ayırır. Satır içi biçim (kalın, kod, link) UI'da
/// `AttributedString(markdown:)` ile işlenir; bloklar burada ayrılır çünkü SwiftUI `Text` başlık/liste/kod
/// bloklarını düzen olarak çizmez. Akış sırasında yarım kod bloğu da güvenle kod olarak gösterilir.
public enum MarkdownBlock: Sendable, Hashable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(language: String?, code: String, isClosed: Bool)
    case listItem(ordered: Bool, marker: String, text: String, depth: Int)
    case quote(String)
    case table(header: [String], rows: [[String]])
    case rule
    /// ```svg / ```html bloğu: sandbox'lı WebView'da çizilir (docs/adr/0003-rendering.md).
    case widget(kind: WidgetKind, source: String)
}

public enum WidgetKind: String, Sendable, Hashable {
    case svg, html
}

public enum MarkdownParser {
    public static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var i = 0

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph.removeAll()
            }
        }
        func flushQuote() {
            if !quote.isEmpty {
                blocks.append(.quote(quote.joined(separator: "\n")))
                quote.removeAll()
            }
        }
        func flushAll() {
            flushParagraph()
            flushQuote()
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Çitli kod bloğu
            if let fence = fenceMarker(trimmed) {
                flushAll()
                let info = String(trimmed.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
                let language = info.split(separator: " ").first.map { String($0).lowercased() }
                var body: [String] = []
                var closed = false
                i += 1
                while i < lines.count {
                    let candidate = lines[i].trimmingCharacters(in: .whitespaces)
                    if candidate.hasPrefix(fence), candidate.allSatisfy({ $0 == fence.first }) {
                        closed = true
                        break
                    }
                    body.append(lines[i])
                    i += 1
                }
                let source = body.joined(separator: "\n")
                if closed, let language, let widget = WidgetKind(rawValue: language) {
                    blocks.append(.widget(kind: widget, source: source))
                } else {
                    blocks.append(.code(language: language?.isEmpty == true ? nil : language, code: source, isClosed: closed))
                }
                i += 1
                continue
            }

            if trimmed.isEmpty {
                flushAll()
                i += 1
                continue
            }

            if let heading = headingLevel(trimmed) {
                flushAll()
                blocks.append(.heading(level: heading, text: String(trimmed.dropFirst(heading + 1))))
                i += 1
                continue
            }

            if isRule(trimmed) {
                flushAll()
                blocks.append(.rule)
                i += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                i += 1
                continue
            }

            if let item = listItem(line) {
                flushAll()
                blocks.append(item)
                i += 1
                continue
            }

            // GFM tablo: başlık satırı + ayırıcı satır
            if trimmed.hasPrefix("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                flushAll()
                let header = tableCells(trimmed)
                var rows: [[String]] = []
                i += 2
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(tableCells(lines[i].trimmingCharacters(in: .whitespaces)))
                    i += 1
                }
                blocks.append(.table(header: header, rows: rows))
                continue
            }

            flushQuote()
            paragraph.append(line)
            i += 1
        }
        flushAll()
        return blocks
    }

    static func fenceMarker(_ line: String) -> String? {
        if line.hasPrefix("```") { return String(line.prefix { $0 == "`" }) }
        if line.hasPrefix("~~~") { return String(line.prefix { $0 == "~" }) }
        return nil
    }

    static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.count > hashes, line[line.index(line.startIndex, offsetBy: hashes)] == " " else { return nil }
        return hashes
    }

    static func isRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    static func listItem(_ line: String) -> MarkdownBlock? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }.count
        let rest = line.dropFirst(indent)
        let depth = indent / 2
        if let marker = rest.first, "-*+".contains(marker), rest.dropFirst().first == " " {
            return .listItem(ordered: false, marker: "•", text: String(rest.dropFirst(2)), depth: depth)
        }
        let digits = rest.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 9 {
            let after = rest.dropFirst(digits.count)
            if let punct = after.first, punct == "." || punct == ")", after.dropFirst().first == " " {
                return .listItem(ordered: true, marker: "\(digits).", text: String(after.dropFirst(2)), depth: depth)
            }
        }
        return nil
    }

    static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("|"), t.contains("-") else { return false }
        return t.allSatisfy { "|-: ".contains($0) }
    }

    static func tableCells(_ line: String) -> [String] {
        var t = line
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
