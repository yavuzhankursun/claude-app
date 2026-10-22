import Foundation
import Testing
@testable import NovaCore

@Suite("Markdown blokları")
struct MarkdownTests {
    @Test func parsesMixedDocument() {
        let text = """
        # Başlık
        Bir **paragraf**
        devam.

        - madde 1
          - iç madde
        1. sıralı

        ```swift
        let x = 1
        ```
        > alıntı
        ---
        | a | b |
        |---|---|
        | 1 | 2 |
        """
        let blocks = MarkdownParser.parse(text)
        #expect(blocks == [
            .heading(level: 1, text: "Başlık"),
            .paragraph("Bir **paragraf**\ndevam."),
            .listItem(ordered: false, marker: "•", text: "madde 1", depth: 0),
            .listItem(ordered: false, marker: "•", text: "iç madde", depth: 1),
            .listItem(ordered: true, marker: "1.", text: "sıralı", depth: 0),
            .code(language: "swift", code: "let x = 1", isClosed: true),
            .quote("alıntı"),
            .rule,
            .table(header: ["a", "b"], rows: [["1", "2"]]),
        ])
    }

    @Test func unclosedFenceWhileStreamingIsCode() {
        let blocks = MarkdownParser.parse("Önce:\n```py\nprint(1)")
        #expect(blocks.last == .code(language: "py", code: "print(1)", isClosed: false))
    }

    @Test func svgFenceBecomesWidgetOnlyWhenClosed() {
        #expect(MarkdownParser.parse("```svg\n<svg/>\n```") == [.widget(kind: .svg, source: "<svg/>")])
        #expect(MarkdownParser.parse("```svg\n<svg") == [.code(language: "svg", code: "<svg", isClosed: false)])
    }
}

@Suite("Widget güvenliği")
struct WidgetTests {
    @Test func stripsActiveContent() {
        let hostile = """
        <svg onload="alert(1)"><script>fetch('https://evil')</script><a href="javascript:alert(1)">x</a>
        <foreignObject><iframe src="https://evil"></iframe></foreignObject><image href="https://evil/p.png"/></svg>
        """
        let html = WidgetDocument.html(for: .svg, source: hostile, dark: true)
        #expect(!html.localizedCaseInsensitiveContains("<script"))
        #expect(!html.localizedCaseInsensitiveContains("onload"))
        #expect(!html.localizedCaseInsensitiveContains("javascript:"))
        #expect(!html.localizedCaseInsensitiveContains("<iframe"))
        #expect(!html.contains("https://evil"))
        #expect(html.contains("default-src 'none'"))
        #expect(html.contains("script-src 'none'"))
    }
}

@Suite("Diff")
struct DiffTests {
    @Test func editDiff() throws {
        let input: JSONValue = ["file_path": "/a.swift", "old_string": "a\nb\nc", "new_string": "a\nB\nc\nd"]
        let diff = try #require(LineDiff.fileDiff(toolName: "Edit", input: input))
        #expect(diff.filePath == "/a.swift")
        #expect(diff.lines.map(\.kind) == [.context, .removed, .added, .context, .added])
        #expect(diff.addedCount == 2)
        #expect(diff.removedCount == 1)
    }

    @Test func collapseKeepsContextAroundChanges() {
        let old = (1...20).map(String.init).joined(separator: "\n")
        let new = old.replacingOccurrences(of: "\n10\n", with: "\nten\n")
        let collapsed = LineDiff.collapse(LineDiff.diff(old: old, new: new), context: 2)
        #expect(collapsed.map(\.text) == ["8", "9", "10", "ten", "11", "12"])
    }
}

@Suite("Sözdizimi vurgulama")
struct HighlighterTests {
    @Test func swiftTokens() {
        let code = "let s = \"hi\" // not\nfunc f() {}"
        let tokens = SyntaxHighlighter.tokenize(code, language: "swift")
        func has(_ text: String, _ kind: TokenKind) -> Bool {
            tokens.contains { String(code[$0.range]) == text && $0.kind == kind }
        }
        #expect(has("let", .keyword))
        #expect(has("\"hi\"", .string))
        #expect(has("// not", .comment))
        #expect(has("func", .keyword))
    }

    @Test func unknownLanguageIsPlain() {
        #expect(SyntaxHighlighter.tokenize("anything", language: "brainfuck").isEmpty)
    }
}
