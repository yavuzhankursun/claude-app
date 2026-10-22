import NovaCore
import SwiftUI

/// Canlı transcript (US-3). `LazyVStack` ile tembel; satırlar `Equatable` olduğundan yalnızca değişen
/// (genellikle son, akan) satır yeniden çizilir. Alta sabitleme `defaultScrollAnchor(.bottom, for: .sizeChanges)` ile.
struct TranscriptView: View {
    let controller: SessionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(controller.transcript.items) { item in
                    TranscriptRow(item: item)
                        .equatable()
                        .id(item.id)
                        .transition(.blurReplace)
                }
            }
            // Yeni satırlar ortak glass yayıyla belirir; akan metin (sayı değişmeden) animasyonsuz güncellenir.
            .animation(Motion.glass(reduceMotion), value: controller.transcript.items.count)
            .frame(maxWidth: Theme.transcriptMaxWidth, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .overlay {
            if controller.transcript.items.isEmpty {
                EmptyTranscript(mode: controller.record.mode)
            }
        }
    }
}

private struct EmptyTranscript: View {
    let mode: SessionMode

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: mode == .chat ? "bubble.left.and.text.bubble.right" : "hammer")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(mode == .chat ? "Bir şey sorun." : "Bu projede ne yapalım?")
                .font(.title3)
                .foregroundStyle(.secondary)
            if mode == .chat {
                Text("Sohbet modu salt-okunur: dosya yazma ve shell kapalı.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .allowsHitTesting(false)
    }
}

struct TranscriptRow: View, Equatable {
    let item: TranscriptItem

    var body: some View {
        switch item.kind {
        case .user(let text):
            UserBubble(text: text)
        case .assistantText(let text):
            MarkdownView(text: text, isStreaming: item.isStreaming)
        case .thinking(let text, let streaming):
            ThinkingBlock(text: text, isStreaming: streaming)
        case .redactedThinking:
            Label("Düşünme bloğu gizlendi", systemImage: "eye.slash")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .novaGlass(in: Capsule(), interactive: false)
        case .toolCall(let call):
            ToolCallCard(call: call)
        case .notice(let notice):
            NoticeRow(notice: notice)
        }
    }
}

struct UserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 80)
            Text(text)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .surface(strong: true)
        }
        .accessibilityLabel(Text("Siz: \(text)"))
    }
}

struct ThinkingBlock: View {
    let text: String
    let isStreaming: Bool
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "brain")
                    .symbolEffect(.pulse, options: .repeat(.continuous), isActive: isStreaming)
                Text(isStreaming ? "Düşünüyor…" : "Düşünme")
                if !expanded, !text.isEmpty {
                    Text(text.suffix(90).replacingOccurrences(of: "\n", with: " "))
                        .lineLimit(1)
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .surface()
    }
}

struct NoticeRow: View {
    let notice: Notice

    var body: some View {
        HStack(spacing: 8) {
            switch notice {
            case .interrupted:
                Image(systemName: "stop.circle")
                Text("Durduruldu")
            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(message).textSelection(.enabled)
            case .info(let message):
                Image(systemName: "info.circle")
                Text(message)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .novaGlass(in: Capsule(), interactive: false)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
