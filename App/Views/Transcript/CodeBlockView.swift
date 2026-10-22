import AppKit
import NovaCore
import SwiftUI

struct CodeBlockView: View {
    let code: String
    let language: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "text")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .frame(width: 26, height: 26)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.novaGlass(shape: .circle))
                .frame(width: 26, height: 26)
                .help("Kopyala")
                .accessibilityLabel(copied ? "Kopyalandı" : "Kodu kopyala")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider().opacity(0.5)

            ScrollView(.horizontal, showsIndicators: true) {
                Text(Self.highlighted(code, language: language))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(12)
            }
        }
        .novaGlass(cornerRadius: Theme.smallCorner, interactive: false)
    }

    static func highlighted(_ code: String, language: String?) -> AttributedString {
        var attributed = AttributedString(code)
        attributed.foregroundColor = Theme.tokenColor(.plain)
        for token in SyntaxHighlighter.tokenize(code, language: language) {
            guard let range = Range(token.range, in: attributed) else { continue }
            attributed[range].foregroundColor = Theme.tokenColor(token.kind.style)
        }
        return attributed
    }
}

extension TokenKind {
    var style: Theme.TokenKindStyle {
        switch self {
        case .keyword: .keyword
        case .string: .string
        case .comment: .comment
        case .number: .number
        case .type: .type
        case .plain: .plain
        }
    }
}
