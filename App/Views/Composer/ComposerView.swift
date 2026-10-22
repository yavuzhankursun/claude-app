import MonsterCore
import SwiftUI

/// Yüzen glass composer. Odaklanınca/metin girilince genişler; gönder düğmesi tur sırasında durdur'a dönüşür.
/// ↩ gönderir, ⇧↩ yeni satır, Esc durdurur. `TextField(axis: .vertical)` içeriğe göre büyür.
struct ComposerView: View {
    @Bindable var controller: SessionController
    let glassNamespace: Namespace.ID
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var expanded: Bool { focused || !controller.draft.isEmpty }
    private var placeholder: LocalizedStringKey {
        controller.record.mode == .chat ? "Claude'a sorun…" : "Claude Code'a bir görev verin…"
    }
    private var canSend: Bool {
        !controller.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !controller.isTurnActive
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                TextField(placeholder, text: $controller.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(expanded ? 1...10 : 1...1)
                    .focused($focused)
                    .onSubmit { Task { await controller.send() } }
                    .onKeyPress(.return, phases: .down) { press in
                        // ⇧↩ yeni satır; düz ↩ onSubmit'e düşer ve gönderir.
                        guard press.modifiers.contains(.shift) else { return .ignored }
                        controller.draft += "\n"
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        guard controller.isTurnActive else { return .ignored }
                        Task { await controller.interrupt() }
                        return .handled
                    }
                    .accessibilityLabel("Mesaj")
                if expanded {
                    ComposerAccessories(controller: controller)
                        .transition(.blurReplace)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .monsterGlass(cornerRadius: expanded ? 22 : 26)
            .glassEffectID("composer", in: glassNamespace)

            sendButton
                .glassEffectID("send", in: glassNamespace)
        }
        .animation(Motion.smooth(reduceMotion), value: expanded)
        .onAppear { focused = true }
    }

    @ViewBuilder
    private var sendButton: some View {
        if controller.isTurnActive {
            Button {
                Task { await controller.interrupt() }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.monsterGlass(shape: .circle))
            .help("Durdur (Esc)")
            .accessibilityLabel("Durdur")
        } else {
            Button {
                Task { await controller.send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.monsterGlass(prominent: true, shape: .circle))
            .disabled(!canSend)
            .help("Gönder (↩)")
            .accessibilityLabel("Gönder")
        }
    }
}

/// Composer genişleyince görünen küçük seçiciler: mod rozeti ve proje adı.
private struct ComposerAccessories: View {
    let controller: SessionController

    var body: some View {
        HStack(spacing: 8) {
            ModeBadge(mode: controller.record.mode, permission: controller.record.permissionMode)
            if let project = controller.record.projectPath {
                Label(URL(filePath: project).lastPathComponent, systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("⇧↩ yeni satır")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

struct ModeBadge: View {
    let mode: SessionMode
    let permission: PermissionMode

    var body: some View {
        Text(style.text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(style.color)
            .monsterGlass(in: Capsule(), tint: style.color.opacity(0.22), interactive: false)
    }

    private var style: (text: LocalizedStringKey, color: Color) {
        switch (mode, permission) {
        case (.chat, _): ("Sohbet · salt-okunur", .secondary)
        case (.code, .ask): ("Ask", .secondary)
        case (.code, .autoEdit): ("Auto-edit", .blue)
        case (.code, .plan): ("Plan", .teal)
        case (.code, .fullAccess): ("Full access", Theme.danger)
        }
    }
}
