import MonsterCore
import SwiftUI

enum ModelChoice: String, CaseIterable, Identifiable {
    case `default` = ""
    case fable, opus, sonnet, haiku

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .default: "Varsayılan"
        case .fable: "Fable"
        case .opus: "Opus"
        case .sonnet: "Sonnet"
        case .haiku: "Haiku"
        }
    }

    /// CLI takma adları her zaman en güncel modele çözülür (`--model fable` vb.).
    var cliValue: String? { self == .default ? nil : rawValue }

    init(cliValue: String?) {
        self = cliValue.flatMap { value in Self.allCases.first { !$0.rawValue.isEmpty && value.localizedCaseInsensitiveContains($0.rawValue) } }
            ?? .default
    }
}

struct ModelMenu: View {
    let controller: SessionController

    var body: some View {
        Menu {
            Picker("Model", selection: Binding(
                get: { ModelChoice(cliValue: controller.record.model) },
                set: { choice in Task { await controller.setModel(choice.cliValue) } }
            )) {
                ForEach(ModelChoice.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label(currentTitle, systemImage: "cpu")
                .labelStyle(.titleAndIcon)
        }
        .help("Model")
    }

    private var currentTitle: String {
        controller.transcript.model ?? controller.record.model ?? String(localized: "Varsayılan")
    }
}

/// Ask / Auto-edit / Full access. Full access ilk kullanımda onay ister ve kırmızı rozetle gösterilir.
struct PermissionModeMenu: View {
    let controller: SessionController
    @AppStorage(SettingsKeys.fullAccessAcknowledged) private var acknowledged = false
    @State private var confirmFullAccess = false

    var body: some View {
        Menu {
            ForEach([PermissionMode.ask, .autoEdit, .plan, .fullAccess]) { mode in
                Button {
                    select(mode)
                } label: {
                    if mode == current { Label(title(mode), systemImage: "checkmark") } else { Text(title(mode)) }
                }
            }
        } label: {
            ModeBadge(mode: .code, permission: current)
        }
        .menuIndicator(.hidden)
        .help("İzin modu")
        .confirmationDialog("Full access açılsın mı?", isPresented: $confirmFullAccess, titleVisibility: .visible) {
            Button("Full access'i aç", role: .destructive) {
                acknowledged = true
                apply(.fullAccess)
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Claude bu projede onay sormadan dosya yazabilir ve shell komutu çalıştırabilir. Yalnızca güvendiğiniz klasörlerde kullanın.")
        }
    }

    private var current: PermissionMode {
        controller.transcript.permissionMode ?? controller.record.permissionMode
    }

    private func select(_ mode: PermissionMode) {
        if mode == .fullAccess && !acknowledged {
            confirmFullAccess = true
        } else {
            apply(mode)
        }
    }

    private func apply(_ mode: PermissionMode) {
        Task { await controller.setPermissionMode(mode) }
    }

    private func title(_ mode: PermissionMode) -> LocalizedStringKey {
        switch mode {
        case .ask: "Ask — her araç için sor"
        case .autoEdit: "Auto-edit — düzenlemeleri otomatik onayla"
        case .plan: "Plan — önce plan, değişiklik yok"
        case .fullAccess: "Full access — hiçbir şey sorma"
        }
    }
}

/// Bağlam doluluğu + maliyet (US-7).
struct UsageGauge: View {
    let controller: SessionController
    @State private var showDetails = false

    var body: some View {
        let t = controller.transcript
        Button {
            showDetails.toggle()
        } label: {
            HStack(spacing: 6) {
                Gauge(value: t.contextFraction) { EmptyView() }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(t.contextFraction > 0.85 ? Theme.danger : t.contextFraction > 0.6 ? .orange : .accentColor)
                    .scaleEffect(0.5)
                    .frame(width: 22, height: 22)
                Text(t.totalCostUSD, format: .currency(code: "USD").precision(.fractionLength(2...4)))
                    .monospacedDigit()
                    .font(.callout)
            }
        }
        .help("Bağlam ve kullanım")
        .accessibilityLabel(Text("Bağlam %\(Int(t.contextFraction * 100)) dolu"))
        .popover(isPresented: $showDetails, arrowEdge: .bottom) {
            UsageDetails(controller: controller)
                .padding(16)
                .frame(width: 280)
        }
    }
}

private struct UsageDetails: View {
    let controller: SessionController

    var body: some View {
        let t = controller.transcript
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text("Bağlam").foregroundStyle(.secondary)
                Text("\(t.contextTokens.formatted()) / \(t.contextWindow.formatted())")
            }
            GridRow {
                Text("Doluluk").foregroundStyle(.secondary)
                ProgressView(value: t.contextFraction)
            }
            GridRow {
                Text("Bu tur çıktı").foregroundStyle(.secondary)
                Text("\(t.outputTokensThisTurn.formatted()) token")
            }
            GridRow {
                Text("Toplam maliyet").foregroundStyle(.secondary)
                Text(t.totalCostUSD, format: .currency(code: "USD").precision(.fractionLength(4)))
            }
            if let ttft = controller.lastFirstTokenLatency {
                GridRow {
                    Text("İlk token").foregroundStyle(.secondary)
                    Text("\(Int(ttft.milliseconds)) ms")
                }
            }
            if let limit = t.rateLimitUtilization {
                GridRow {
                    Text("Limit kullanımı").foregroundStyle(.secondary)
                    Text(limit, format: .percent.precision(.fractionLength(0)))
                }
            }
            if let version = controller.cliVersion {
                GridRow {
                    Text("CLI").foregroundStyle(.secondary)
                    Text(version)
                }
            }
        }
        .font(.callout)
        .monospacedDigit()
    }
}
