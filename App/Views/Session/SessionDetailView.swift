import MonsterCore
import SwiftUI

/// Bir session'ın ana görünümü: transcript (düz yüzeyler) + yüzen glass katman (izin kartı, durum pili, composer).
struct SessionDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKeys.prewarm) private var prewarm = true
    let controller: SessionController
    @Namespace private var glassNamespace

    var body: some View {
        TranscriptView(controller: controller)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 10) {
                        if let request = controller.pendingPermission {
                            PermissionCard(request: request) { decision in
                                Task { await controller.decide(decision, for: request) }
                            }
                            .glassEffectID("permission", in: glassNamespace)
                            .transition(.blurReplace)
                        }
                        StatusPill(controller: controller)
                            .glassEffectID("status", in: glassNamespace)
                        ComposerView(controller: controller, glassNamespace: glassNamespace)
                    }
                    .frame(maxWidth: Theme.transcriptMaxWidth)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
                .animation(Motion.smooth(reduceMotion), value: controller.pendingPermission?.requestId)
                .animation(Motion.smooth(reduceMotion), value: controller.isTurnActive)
            }
            .navigationTitle(controller.record.title)
            .navigationSubtitle(subtitle)
            .toolbar { SessionToolbar(controller: controller) }
            .focusedSceneValue(\.activeSession, controller)
            .task {
                await controller.loadHistoryIfNeeded()
                if prewarm, case .found = model.cliStatus { await controller.prewarm() }
            }
            .onDisappear { model.save() }
    }

    private var subtitle: String {
        switch controller.record.mode {
        case .chat: String(localized: "Sohbet")
        case .code: controller.record.projectPath.map(AppModel.abbreviate) ?? ""
        }
    }
}

/// "Düşünüyor" pili: tur boyunca durumunu akıcı biçimde değiştirir (glass morph).
struct StatusPill: View {
    let controller: SessionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let state = activity {
            HStack(spacing: 8) {
                Image(systemName: state.symbol)
                    .symbolEffect(.variableColor.iterative, options: .repeat(.continuous), isActive: !reduceMotion)
                    .contentTransition(.symbolEffect(.replace))
                Text(state.label)
                    .contentTransition(.interpolate)
                    .lineLimit(1)
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .monsterGlass(in: Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.blurReplace)
            .accessibilityElement(children: .combine)
        } else if case .exited(let message?) = controller.phase {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(Theme.warning)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .monsterGlass(in: Capsule(), tint: Theme.warning.opacity(0.14))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var activity: (symbol: String, label: String)? {
        guard controller.isTurnActive else { return nil }
        if controller.pendingPermission != nil { return ("hand.raised", String(localized: "İzin bekleniyor")) }
        guard let last = controller.transcript.items.last else { return ("ellipsis", String(localized: "Düşünüyor…")) }
        switch last.kind {
        case .thinking: return ("brain", String(localized: "Düşünüyor…"))
        case .assistantText: return ("text.cursor", String(localized: "Yazıyor…"))
        case .toolCall(let call) where !call.status.isTerminal:
            return (call.kind.symbolName, String(localized: "\(call.name) çalışıyor"))
        default: return ("ellipsis", String(localized: "Düşünüyor…"))
        }
    }
}

struct SessionToolbar: ToolbarContent {
    let controller: SessionController

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            UsageGauge(controller: controller)
        }
        ToolbarSpacer(.fixed)
        ToolbarItem(placement: .primaryAction) {
            if controller.record.mode == .code {
                PermissionModeMenu(controller: controller)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            ModelMenu(controller: controller)
        }
        ToolbarSpacer(.fixed)
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await controller.interrupt() }
            } label: {
                Label("Durdur", systemImage: "stop.fill")
            }
            .disabled(!controller.isTurnActive)
            .help("Durdur (Esc)")
        }
    }
}
