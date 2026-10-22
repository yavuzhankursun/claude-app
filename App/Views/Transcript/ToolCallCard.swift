import MonsterCore
import SwiftUI

/// Katlanabilir araç kartı (Bash/Edit/Read…). Düz yüzey; glass değil.
struct ToolCallCard: View {
    let call: ToolCall
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.glass(reduceMotion)) { expanded.toggle() }
            } label: {
                header
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Daralt" : "Genişlet")

            if expanded || showsDiffInline {
                Divider().opacity(0.4)
                ToolCallBody(call: call)
                    .padding(12)
                    .transition(.blurReplace)
            }
        }
        .surface()
    }

    /// Edit/Write kartları diff'i varsayılan olarak açık gösterir (kısa ise).
    private var showsDiffInline: Bool {
        guard call.kind == .edit || call.kind == .write, call.status != .denied else { return false }
        guard let diff = LineDiff.fileDiff(toolName: call.name, input: call.input) else { return false }
        return diff.lines.count <= 40
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: call.kind.symbolName)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(call.name)
                .fontWeight(.medium)
            Text(call.summary)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if call.subagentMessageCount > 0 {
                Text("\(call.subagentMessageCount) alt mesaj")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if let diff = LineDiff.fileDiff(toolName: call.name, input: call.input) {
                DiffStat(added: diff.addedCount, removed: diff.removedCount)
            }
            StatusBadge(status: call.status)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(.rect)
    }
}

private struct ToolCallBody: View {
    let call: ToolCall

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let diff = LineDiff.fileDiff(toolName: call.name, input: call.input) {
                DiffView(diff: diff)
            } else if call.kind == .bash, let command = call.input?["command"]?.stringValue {
                CodeBlockView(code: command, language: "bash")
            } else if let input = call.input {
                CodeBlockView(code: input.prettyString(), language: "json")
            } else if !call.partialInput.isEmpty {
                CodeBlockView(code: call.partialInput, language: "json")
            }

            if let result = call.result, !result.text.isEmpty || result.imageCount > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text(call.status == .failed ? "Hata" : "Çıktı")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(Self.clip(result.text))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(call.status == .failed ? AnyShapeStyle(Color.yellow) : AnyShapeStyle(.secondary))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 260)
                    if result.imageCount > 0 {
                        Label("\(result.imageCount) görsel", systemImage: "photo")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    /// Çok uzun çıktılar (ör. log) kare kaybı yaratmasın.
    static func clip(_ text: String, limit: Int = 20_000) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "\n… (\(text.count - limit) karakter kırpıldı)"
    }
}

struct StatusBadge: View {
    let status: ToolCall.Status

    var body: some View {
        Group {
            switch status {
            case .streamingInput, .running:
                ProgressView().controlSize(.small)
            case .awaitingPermission:
                Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            case .succeeded:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(.symbolEffect(.drawOn))
            case .failed:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.yellow)
            case .denied:
                Image(systemName: "nosign").foregroundStyle(Theme.danger)
            case .cancelled:
                Image(systemName: "stop.circle").foregroundStyle(.secondary)
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityLabel(label)
    }

    private var label: Text {
        switch status {
        case .streamingInput, .running: Text("Çalışıyor")
        case .awaitingPermission: Text("İzin bekleniyor")
        case .succeeded: Text("Tamamlandı")
        case .failed: Text("Hata")
        case .denied: Text("Reddedildi")
        case .cancelled: Text("İptal edildi")
        }
    }
}

struct DiffStat: View {
    let added: Int
    let removed: Int

    var body: some View {
        HStack(spacing: 4) {
            Text("+\(added)").foregroundStyle(Theme.diffAdded)
            Text("−\(removed)").foregroundStyle(Theme.diffRemoved)
        }
        .font(.caption.monospacedDigit())
    }
}
