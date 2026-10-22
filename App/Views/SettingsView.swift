import NovaCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Genel", systemImage: "gearshape") { GeneralSettings() }
            Tab("Güvenlik", systemImage: "lock.shield") { SecuritySettings() }
        }
        .frame(width: 520, height: 360)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKeys.cliPath) private var cliPath = ""
    @AppStorage(SettingsKeys.defaultModel) private var defaultModel = ""
    @AppStorage(SettingsKeys.defaultEffort) private var defaultEffort = ""
    @AppStorage(SettingsKeys.defaultPermission) private var defaultPermission = PermissionMode.ask.rawValue
    @AppStorage(SettingsKeys.prewarm) private var prewarm = true

    var body: some View {
        Form {
            Section("Claude Code CLI") {
                TextField("Yol (boş = otomatik bul)", text: $cliPath, prompt: Text("~/.local/bin/claude"))
                    .onSubmit { Task { await model.checkCLI() } }
                CLIStatusView(status: model.cliStatus)
                Button("Yeniden ara") { Task { await model.checkCLI() } }
            }
            Section("Varsayılanlar") {
                Picker("Model", selection: $defaultModel) {
                    ForEach(ModelChoice.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Effort", selection: $defaultEffort) {
                    Text("Varsayılan").tag("")
                    ForEach(Effort.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Picker("İzin modu (Kod)", selection: $defaultPermission) {
                    Text("Ask").tag(PermissionMode.ask.rawValue)
                    Text("Auto-edit").tag(PermissionMode.autoEdit.rawValue)
                    Text("Plan").tag(PermissionMode.plan.rawValue)
                }
                Toggle("Session açılınca CLI'ı önceden başlat (daha hızlı ilk cevap)", isOn: $prewarm)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SecuritySettings: View {
    @AppStorage(SettingsKeys.fullAccessAcknowledged) private var fullAccessAcknowledged = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Kimlik") {
                    Text("Nova API anahtarı tutmaz; kurulu `claude` CLI'ının girişini kullanır.")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Loglar") {
                    Text("Yalnızca meta veri (mod, araç adı, süre). Prompt ve dosya içeriği loglanmaz.")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Widget'lar") {
                    Text("SVG/HTML, JavaScript ve ağ erişimi kapalı bir WebView'da çizilir.")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Full access") {
                Toggle("Full access uyarısı onaylandı", isOn: $fullAccessAcknowledged)
                Text("Kapatırsanız Full access bir sonraki seçimde yeniden onay ister.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
