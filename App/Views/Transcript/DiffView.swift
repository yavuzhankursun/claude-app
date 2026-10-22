import MonsterCore
import SwiftUI

/// Edit/MultiEdit/Write için birleşik (unified) diff görünümü.
struct DiffView: View {
    let diff: FileDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "doc.text")
                Text(AppModel.abbreviate(diff.filePath))
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                DiffStat(added: diff.addedCount, removed: diff.removedCount)
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider().opacity(0.5)

            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleLines) { line in
                        DiffLineRow(line: line)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 360)
        }
        .monsterGlass(cornerRadius: Theme.smallCorner, interactive: false)
    }

    private var visibleLines: [DiffLine] {
        let collapsed = LineDiff.collapse(diff.lines)
        return collapsed.isEmpty ? diff.lines : collapsed
    }
}

private struct DiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            Text(line.oldNumber.map(String.init) ?? "")
                .frame(width: 38, alignment: .trailing)
                .foregroundStyle(.tertiary)
            Text(line.newNumber.map(String.init) ?? "")
                .frame(width: 38, alignment: .trailing)
                .foregroundStyle(.tertiary)
            Text(sign)
                .frame(width: 18)
                .foregroundStyle(color)
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(line.kind == .context ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.primary))
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.vertical, 1)
        .background(background)
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(accessibilityKind): \(line.text)"))
    }

    private var sign: String {
        switch line.kind {
        case .added: "+"
        case .removed: "−"
        case .context: " "
        }
    }

    private var color: Color {
        switch line.kind {
        case .added: Theme.diffAdded
        case .removed: Theme.diffRemoved
        case .context: .secondary
        }
    }

    private var background: Color {
        switch line.kind {
        case .added: Theme.diffAdded.opacity(0.12)
        case .removed: Theme.diffRemoved.opacity(0.12)
        case .context: .clear
        }
    }

    private var accessibilityKind: String {
        switch line.kind {
        case .added: String(localized: "Eklendi")
        case .removed: String(localized: "Silindi")
        case .context: String(localized: "Değişmedi")
        }
    }
}
