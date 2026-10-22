import MonsterCore
import SwiftData
import SwiftUI

@main
struct MonsterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer
    @State private var model: AppModel

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: SessionRecord.self)
        } catch {
            // Şema bozulursa uygulama yine açılsın; meta veri bellekte tutulur, CLI geçmişi etkilenmez.
            container = try! ModelContainer(for: SessionRecord.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        self.container = container
        let model = AppModel(context: container.mainContext)
        _model = State(initialValue: model)
        AppDelegate.shared = model
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(model)
                .task { await model.bootstrap() }
                .frame(minWidth: 820, minHeight: 520)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
        .windowToolbarStyle(.unified)
        .commands { MonsterCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = Self.shared else { return .terminateNow }
        // Alt süreçler kapanmadan çıkılmaz; yetim `claude` süreci bırakılmaz.
        Task { @MainActor in
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
