import Foundation

/// Edit/MultiEdit/Write araç girdilerinden satır bazlı diff. Swift stdlib'in `CollectionDifference`
/// (Myers) algoritması kullanılır; ek bağımlılık yok.
public struct DiffLine: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable { case context, added, removed }
    public var id: Int
    public var kind: Kind
    public var text: String
    public var oldNumber: Int?
    public var newNumber: Int?
}

public struct FileDiff: Sendable, Hashable {
    public var filePath: String
    public var lines: [DiffLine]
    public var addedCount: Int { lines.count(where: { $0.kind == .added }) }
    public var removedCount: Int { lines.count(where: { $0.kind == .removed }) }
}

public enum LineDiff {
    /// Çok büyük girdilerde kare kaybını önlemek için üst sınır (satır).
    public static let maxLines = 4_000

    public static func diff(old: String, new: String) -> [DiffLine] {
        let a = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let b = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if a.count > maxLines || b.count > maxLines {
            return a.enumerated().map { DiffLine(id: $0.offset, kind: .removed, text: $0.element, oldNumber: $0.offset + 1, newNumber: nil) }
                + b.enumerated().map { DiffLine(id: a.count + $0.offset, kind: .added, text: $0.element, oldNumber: nil, newNumber: $0.offset + 1) }
        }

        let difference = b.difference(from: a)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var result: [DiffLine] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, removed.contains(i) {
                result.append(DiffLine(id: result.count, kind: .removed, text: a[i], oldNumber: i + 1, newNumber: nil))
                i += 1
            } else if j < b.count, inserted.contains(j) {
                result.append(DiffLine(id: result.count, kind: .added, text: b[j], oldNumber: nil, newNumber: j + 1))
                j += 1
            } else if i < a.count, j < b.count {
                result.append(DiffLine(id: result.count, kind: .context, text: a[i], oldNumber: i + 1, newNumber: j + 1))
                i += 1
                j += 1
            } else {
                break
            }
        }
        return result
    }

    /// Bağlamı `context` satıra indirger; aradaki uzun eşit bölgeler atlanır.
    public static func collapse(_ lines: [DiffLine], context: Int = 3) -> [DiffLine] {
        let changed = lines.indices.filter { lines[$0].kind != .context }
        guard !changed.isEmpty else { return [] }
        var keep = Set<Int>()
        for idx in changed {
            for k in max(0, idx - context)...min(lines.count - 1, idx + context) { keep.insert(k) }
        }
        return lines.indices.filter(keep.contains).map { lines[$0] }
    }

    /// Bir araç çağrısından gösterilebilir diff üretir; desteklenmeyen araçlarda `nil`.
    public static func fileDiff(toolName: String, input: JSONValue?) -> FileDiff? {
        guard let input, let path = input["file_path"]?.stringValue ?? input["notebook_path"]?.stringValue else { return nil }
        switch toolName {
        case "Edit":
            guard let old = input["old_string"]?.stringValue, let new = input["new_string"]?.stringValue else { return nil }
            return FileDiff(filePath: path, lines: diff(old: old, new: new))
        case "MultiEdit":
            guard let edits = input["edits"]?.arrayValue else { return nil }
            var lines: [DiffLine] = []
            for edit in edits {
                guard let old = edit["old_string"]?.stringValue, let new = edit["new_string"]?.stringValue else { continue }
                let offset = lines.count
                lines += diff(old: old, new: new).map { line in
                    var l = line
                    l.id += offset
                    return l
                }
            }
            return FileDiff(filePath: path, lines: lines)
        case "Write":
            guard let content = input["content"]?.stringValue else { return nil }
            return FileDiff(filePath: path, lines: diff(old: "", new: content).filter { !($0.kind == .removed && $0.text.isEmpty) })
        default:
            return nil
        }
    }
}
