import NovaCore
import SwiftUI

extension FocusedValues {
    @Entry var windowState: WindowState?
    @Entry var activeSession: SessionController?
}

/// Menü çubuğu komutları. Pencereye özgü eylemler `FocusedValue` üzerinden o pencerenin durumuna gider.
struct NovaCommands: Commands {
    @FocusedValue(\.windowState) private var window
    @FocusedValue(\.activeSession) private var session
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Yeni Kod Session'ı") {
                window?.newSessionMode = .code
                window?.showNewSession = true
            }
            .keyboardShortcut("n")
            .disabled(window == nil)

            Button("Yeni Sohbet") {
                window?.newSessionMode = .chat
                window?.showNewSession = true
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(window == nil)
        }

        CommandMenu("Session") {
            Button("Komut Paleti") { window?.showPalette.toggle() }
                .keyboardShortcut("k")
                .disabled(window == nil)

            Divider()

            Button("Durdur") { Task { await session?.interrupt() } }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(session?.isTurnActive != true)

            Divider()

            ForEach(1..<10) { index in
                Button("Session \(index)") { selectSession(at: index - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
                    .disabled(window == nil)
            }
        }
    }

    /// ⌘1…9: kenar çubuğundaki sıraya göre Nova session'ları.
    private func selectSession(at index: Int) {
        guard let window else { return }
        let ordered = model.sections(matching: window.sidebarQuery).flatMap(\.records)
        guard ordered.indices.contains(index) else { return }
        window.selection = .record(ordered[index].id)
    }
}
