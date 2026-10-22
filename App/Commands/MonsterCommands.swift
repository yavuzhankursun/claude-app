import MonsterCore
import SwiftUI

// Elle yazılmış anahtarlar: varsayılan MainActor izolasyonunda `@Entry` makrosunun ürettiği anahtar
// tiplerinin izolasyonuna güvenmek yerine açıkça `nonisolated`.
nonisolated struct WindowStateFocusKey: FocusedValueKey {
    typealias Value = WindowState
}

nonisolated struct ActiveSessionFocusKey: FocusedValueKey {
    typealias Value = SessionController
}

extension FocusedValues {
    var windowState: WindowState? {
        get { self[WindowStateFocusKey.self] }
        set { self[WindowStateFocusKey.self] = newValue }
    }

    var activeSession: SessionController? {
        get { self[ActiveSessionFocusKey.self] }
        set { self[ActiveSessionFocusKey.self] = newValue }
    }
}

/// Menü çubuğu komutları. Pencereye özgü eylemler `FocusedValue` üzerinden o pencerenin durumuna gider.
struct MonsterCommands: Commands {
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

    /// ⌘1…9: kenar çubuğundaki sıraya göre Monster session'ları.
    private func selectSession(at index: Int) {
        guard let window else { return }
        let ordered = model.sections(matching: window.sidebarQuery).flatMap(\.records)
        guard ordered.indices.contains(index) else { return }
        window.selection = .record(ordered[index].id)
    }
}
