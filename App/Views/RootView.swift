import NovaCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var window = WindowState()
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var window = window
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(window: window)
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 380)
        } detail: {
            ZStack {
                NovaBackground()
                detail
            }
        }
        .overlay {
            if window.showPalette {
                CommandPalette(window: window)
                    .transition(.blurReplace)
            }
        }
        .animation(Motion.glass(reduceMotion), value: window.showPalette)
        .sheet(isPresented: $window.showNewSession) {
            NewSessionSheet(initialMode: window.newSessionMode) { record in
                window.selection = .record(record.id)
            }
        }
        .onChange(of: window.selection) { _, selection in
            // Terminal session'ı seçildiğinde Nova'ya aktarılır ve kayıt olarak seçilir.
            if case .terminal(let sessionId)? = selection,
               let entry = model.terminalEntries.first(where: { $0.sessionId == sessionId }) {
                let record = model.importTerminalSession(entry)
                window.selection = .record(record.id)
            }
        }
        .focusedSceneValue(\.windowState, window)
    }

    @ViewBuilder
    private var detail: some View {
        if case .record(let id)? = window.selection, let record = model.record(id: id) {
            SessionDetailView(controller: model.controller(for: record))
                .id(record.id)
        } else {
            WelcomeView(window: window)
        }
    }
}

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    let window: WindowState

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "sparkle")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.tint)
                .symbolEffect(.breathe, options: .repeat(.continuous))
            Text("Nova")
                .font(.largeTitle.weight(.semibold))
            Text("Claude Code için yerel bir macOS istemcisi.")
                .foregroundStyle(.secondary)

            GlassEffectContainer(spacing: 14) {
                HStack(spacing: 14) {
                    Button {
                        window.newSessionMode = .chat
                        window.showNewSession = true
                    } label: {
                        Label("Sohbet", systemImage: "bubble.left.and.text.bubble.right")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.novaGlass)
                    .controlSize(.large)

                    Button {
                        window.newSessionMode = .code
                        window.showNewSession = true
                    } label: {
                        Label("Kod", systemImage: "chevron.left.forwardslash.chevron.right")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.novaGlassProminent)
                    .controlSize(.large)
                }
            }

            CLIStatusView(status: model.cliStatus)
                .padding(.top, 8)
        }
        .padding(40)
    }
}

struct CLIStatusView: View {
    let status: AppModel.CLIStatus

    var body: some View {
        switch status {
        case .checking:
            Label("Claude Code aranıyor…", systemImage: "magnifyingglass")
                .foregroundStyle(.secondary)
        case .found(let version, let tested):
            if tested {
                Label("Claude Code \(version ?? "?")", systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
            } else {
                Label("Claude Code \(version ?? "?") — Nova \(CLILocator.testedVersion) ile test edildi; akış formatı farklı olabilir.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.yellow)
            }
        case .missing:
            Label("Claude Code CLI bulunamadı. Kurup terminalde bir kez `claude` ile giriş yapın; ya da Ayarlar'dan yolu belirtin.",
                  systemImage: "xmark.octagon")
                .foregroundStyle(Theme.danger)
                .multilineTextAlignment(.center)
        }
    }
}
