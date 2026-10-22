import MonsterCore
import SwiftUI
import UniformTypeIdentifiers

/// US-2: Sohbet ya da Kod modu, proje klasörü, model, effort ve izin modu.
struct NewSessionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.defaultModel) private var defaultModel = ""
    @AppStorage(SettingsKeys.defaultEffort) private var defaultEffort = ""
    @AppStorage(SettingsKeys.defaultPermission) private var defaultPermission = PermissionMode.ask.rawValue
    @AppStorage(SettingsKeys.fullAccessAcknowledged) private var fullAccessAcknowledged = false

    let onCreate: (SessionRecord) -> Void

    @State private var mode: SessionMode
    @State private var folder: URL?
    @State private var modelChoice: ModelChoice = .default
    @State private var effort: Effort?
    @State private var permission: PermissionMode = .ask
    @State private var pickingFolder = false
    @State private var error: String?
    @State private var confirmFullAccess = false

    init(initialMode: SessionMode, onCreate: @escaping (SessionRecord) -> Void) {
        _mode = State(initialValue: initialMode)
        self.onCreate = onCreate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Yeni session")
                .font(.title2.weight(.semibold))

            Picker("Mod", selection: $mode) {
                Label("Sohbet", systemImage: "bubble.left.and.text.bubble.right").tag(SessionMode.chat)
                Label("Kod", systemImage: "chevron.left.forwardslash.chevron.right").tag(SessionMode.code)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Form {
                if mode == .code {
                    LabeledContent("Proje klasörü") {
                        HStack {
                            Text(folder.map { AppModel.abbreviate($0.path) } ?? String(localized: "Seçilmedi"))
                                .foregroundStyle(folder == nil ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.primary)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Button("Seç…") { pickingFolder = true }
                                .buttonStyle(.monsterGlass)
                        }
                    }
                    Picker("İzin modu", selection: $permission) {
                        Text("Ask").tag(PermissionMode.ask)
                        Text("Auto-edit").tag(PermissionMode.autoEdit)
                        Text("Plan").tag(PermissionMode.plan)
                        Text("Full access").tag(PermissionMode.fullAccess)
                    }
                    if permission == .fullAccess {
                        Label("Full access: Claude onay sormadan dosya yazar ve komut çalıştırır.", systemImage: "exclamationmark.shield.fill")
                            .foregroundStyle(Theme.danger)
                            .font(.callout)
                    }
                } else {
                    Label("Sohbet modu salt-okunurdur: ayrı, boş bir çalışma dizini; dosya yazma ve shell kapalı.",
                          systemImage: "lock")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }

                Picker("Model", selection: $modelChoice) {
                    ForEach(ModelChoice.allCases) { Text($0.title).tag($0) }
                }
                Picker("Effort", selection: $effort) {
                    Text("Varsayılan").tag(Effort?.none)
                    ForEach(Effort.allCases) { Text($0.rawValue).tag(Effort?.some($0)) }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            if let error {
                Text(error).foregroundStyle(Theme.danger).font(.callout)
            }

            HStack {
                Spacer()
                Button("Vazgeç", role: .cancel) { dismiss() }
                    .buttonStyle(.monsterGlass)
                    .keyboardShortcut(.cancelAction)
                Button("Başlat") { create() }
                    .buttonStyle(.monsterGlassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(mode == .code && folder == nil)
            }
        }
        .padding(24)
        .frame(width: 520)
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { folder = url }
        }
        .confirmationDialog("Full access açılsın mı?", isPresented: $confirmFullAccess, titleVisibility: .visible) {
            Button("Full access ile başlat", role: .destructive) {
                fullAccessAcknowledged = true
                create()
            }
        } message: {
            Text("Claude bu projede onay sormadan dosya yazabilir ve shell komutu çalıştırabilir.")
        }
        .onAppear {
            modelChoice = ModelChoice(rawValue: defaultModel) ?? .default
            effort = Effort(rawValue: defaultEffort)
            permission = PermissionMode(rawValue: defaultPermission) ?? .ask
        }
    }

    private func create() {
        if mode == .code, permission == .fullAccess, !fullAccessAcknowledged {
            confirmFullAccess = true
            return
        }
        do {
            let record = try model.createSession(mode: mode, folder: folder, model: modelChoice.cliValue,
                                                 effort: effort, permissionMode: permission)
            onCreate(record)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
