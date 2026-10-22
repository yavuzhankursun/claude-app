import NovaCore
import SwiftUI

/// Asistan metni (US-6). Blok ayrımı NovaCore'da, satır içi biçim native `AttributedString(markdown:)` ile.
struct MarkdownView: View {
    let text: String
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownParser.parse(text).enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

private struct BlockView: View {
    let block: MarkdownBlock

    static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: Font.title2.weight(.semibold)
        case 2: Font.title3.weight(.semibold)
        default: Font.headline
        }
    }

    var body: some View {
        switch block {
        case .heading(let level, let text):
            InlineText(text)
                .font(Self.headingFont(level))
                .padding(.top, level <= 2 ? 6 : 2)
        case .paragraph(let text):
            InlineText(text)
                .lineSpacing(3)
        case .code(let language, let code, _):
            CodeBlockView(code: code, language: language)
        case .listItem(_, let marker, let text, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                InlineText(text)
            }
            .padding(.leading, CGFloat(depth) * 18)
        case .quote(let text):
            InlineText(text)
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1).fill(.tertiary).frame(width: 3)
                }
        case .table(let header, let rows):
            MarkdownTable(header: header, rows: rows)
        case .rule:
            Divider()
        case .widget(let kind, let source):
            WidgetView(kind: kind, source: source)
        }
    }
}

/// Satır içi Markdown (kalın, italik, `kod`, link). Çözümlenemezse düz metin.
struct InlineText: View {
    let source: String
    init(_ source: String) { self.source = source }

    var body: some View {
        Text(Self.attributed(source))
    }

    static func attributed(_ source: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        guard var attributed = try? AttributedString(markdown: source, options: options) else {
            return AttributedString(source)
        }
        let codeRanges = attributed.runs
            .filter { $0.inlinePresentationIntent?.contains(.code) == true }
            .map(\.range)
        for range in codeRanges {
            attributed[range].font = Font.system(.body, design: .monospaced)
            attributed[range].backgroundColor = Theme.surfaceStrong
        }
        return attributed
    }
}

private struct MarkdownTable: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        InlineText(cell).fontWeight(.semibold)
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            InlineText(cell)
                        }
                    }
                }
            }
            .padding(12)
        }
        .surface()
    }
}
