import Foundation

/// Bağımlılıksız, hızlı ve "yeterince iyi" sözcüksel vurgulayıcı. Tam bir dil çözümleyicisi değildir;
/// amaç okunurluk. Çıktı UTF-16 aralıkları değil `String.Index` aralıklarıdır; UI `AttributedString`e uygular.
public enum TokenKind: Sendable, Hashable {
    case keyword, string, comment, number, type, plain
}

public struct SyntaxToken: Sendable, Hashable {
    public var range: Range<String.Index>
    public var kind: TokenKind
}

public enum SyntaxHighlighter {
    struct Grammar {
        var keywords: Set<String>
        var lineComments: [String]
        var blockComment: (open: String, close: String)?
        var stringDelimiters: [Character]
    }

    static let cLikeComments = ["//"]
    static let hashComments = ["#"]

    static func grammar(for language: String?) -> Grammar? {
        switch language?.lowercased() {
        case "swift":
            return Grammar(keywords: ["let", "var", "func", "struct", "class", "enum", "protocol", "extension", "import", "return",
                                      "if", "else", "guard", "switch", "case", "default", "for", "in", "while", "do", "try",
                                      "catch", "throw", "throws", "async", "await", "actor", "public", "private", "internal",
                                      "fileprivate", "static", "self", "Self", "nil", "true", "false", "some", "any", "init",
                                      "deinit", "where", "break", "continue", "defer", "mutating", "final", "override", "typealias"],
                           lineComments: cLikeComments, blockComment: ("/*", "*/"), stringDelimiters: ["\""])
        case "js", "javascript", "ts", "typescript", "jsx", "tsx", "json":
            return Grammar(keywords: ["const", "let", "var", "function", "return", "if", "else", "for", "while", "do", "switch",
                                      "case", "default", "break", "continue", "new", "class", "extends", "import", "export",
                                      "from", "async", "await", "try", "catch", "finally", "throw", "typeof", "instanceof",
                                      "null", "undefined", "true", "false", "this", "interface", "type", "enum", "implements"],
                           lineComments: cLikeComments, blockComment: ("/*", "*/"), stringDelimiters: ["\"", "'", "`"])
        case "py", "python":
            return Grammar(keywords: ["def", "class", "return", "if", "elif", "else", "for", "while", "in", "import", "from",
                                      "as", "with", "try", "except", "finally", "raise", "lambda", "yield", "async", "await",
                                      "None", "True", "False", "and", "or", "not", "is", "pass", "break", "continue", "self"],
                           lineComments: hashComments, blockComment: nil, stringDelimiters: ["\"", "'"])
        case "sh", "bash", "zsh", "shell", "console":
            return Grammar(keywords: ["if", "then", "else", "elif", "fi", "for", "do", "done", "while", "case", "esac",
                                      "function", "return", "export", "local", "in", "echo", "cd", "sudo"],
                           lineComments: hashComments, blockComment: nil, stringDelimiters: ["\"", "'"])
        case "go", "rust", "rs", "c", "cpp", "c++", "h", "java", "kotlin", "kt", "cs", "csharp", "objc", "m":
            return Grammar(keywords: ["func", "fn", "let", "mut", "var", "const", "struct", "enum", "impl", "trait", "pub",
                                      "use", "mod", "return", "if", "else", "for", "while", "loop", "match", "switch", "case",
                                      "default", "break", "continue", "package", "import", "class", "interface", "public",
                                      "private", "protected", "static", "void", "int", "bool", "true", "false", "null",
                                      "nil", "new", "this", "self", "go", "defer", "type", "namespace", "using", "include"],
                           lineComments: cLikeComments, blockComment: ("/*", "*/"), stringDelimiters: ["\"", "'"])
        case "sql":
            return Grammar(keywords: ["select", "from", "where", "join", "left", "right", "inner", "outer", "on", "group",
                                      "by", "order", "having", "insert", "into", "values", "update", "set", "delete",
                                      "create", "table", "index", "and", "or", "not", "null", "as", "limit", "with"],
                           lineComments: ["--"], blockComment: ("/*", "*/"), stringDelimiters: ["'"])
        case "yaml", "yml", "toml", "ruby", "rb":
            return Grammar(keywords: ["true", "false", "null", "def", "end", "class", "module", "if", "else", "do"],
                           lineComments: hashComments, blockComment: nil, stringDelimiters: ["\"", "'"])
        default:
            return nil
        }
    }

    /// Çok uzun bloklarda (ör. 200 KB log) vurgulama atlanır; düz metin daha hızlı ve okunur.
    public static let maxHighlightLength = 60_000

    public static func tokenize(_ code: String, language: String?) -> [SyntaxToken] {
        guard code.utf8.count <= maxHighlightLength, let grammar = grammar(for: language) else { return [] }
        let caseInsensitive = language?.lowercased() == "sql"
        var tokens: [SyntaxToken] = []
        var i = code.startIndex

        func starts(_ s: String, at idx: String.Index) -> Bool { code[idx...].hasPrefix(s) }

        while i < code.endIndex {
            let c = code[i]

            if let block = grammar.blockComment, starts(block.open, at: i) {
                let searchStart = code.index(i, offsetBy: block.open.count)
                let end = code.range(of: block.close, range: searchStart..<code.endIndex)?.upperBound ?? code.endIndex
                tokens.append(SyntaxToken(range: i..<end, kind: .comment))
                i = end
                continue
            }
            if grammar.lineComments.contains(where: { starts($0, at: i) }) {
                let end = code[i...].firstIndex(of: "\n") ?? code.endIndex
                tokens.append(SyntaxToken(range: i..<end, kind: .comment))
                i = end
                continue
            }
            if grammar.stringDelimiters.contains(c) {
                var j = code.index(after: i)
                while j < code.endIndex, code[j] != c {
                    if code[j] == "\\" { j = code.index(after: j); if j == code.endIndex { break } }
                    if code[j] == "\n", c != "`" { break }
                    j = code.index(after: j)
                }
                let end = j < code.endIndex ? code.index(after: j) : code.endIndex
                tokens.append(SyntaxToken(range: i..<end, kind: .string))
                i = end
                continue
            }
            if c.isNumber {
                var j = i
                while j < code.endIndex, code[j].isNumber || code[j] == "." || code[j] == "_" || code[j].isHexDigit || code[j] == "x" {
                    j = code.index(after: j)
                }
                tokens.append(SyntaxToken(range: i..<j, kind: .number))
                i = j
                continue
            }
            if c.isLetter || c == "_" || c == "@" {
                var j = code.index(after: i)
                while j < code.endIndex, code[j].isLetter || code[j].isNumber || code[j] == "_" { j = code.index(after: j) }
                let word = String(code[i..<j])
                let lookup = caseInsensitive ? word.lowercased() : word
                if grammar.keywords.contains(lookup) {
                    tokens.append(SyntaxToken(range: i..<j, kind: .keyword))
                } else if let first = word.first, first.isUppercase {
                    tokens.append(SyntaxToken(range: i..<j, kind: .type))
                }
                i = j
                continue
            }
            i = code.index(after: i)
        }
        return tokens
    }
}
