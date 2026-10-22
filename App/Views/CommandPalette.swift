import MonsterCore
import SwiftUI

/// ⌘K komut paleti: session'lar arası geçiş ve temel komutlar. Glass panel (yüzen katman).
struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    let window: WindowState
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    struct Entry: Identifiable {
        var id: String
        var title: String
        var subtitle: String?
        var symbol: String
        var action: () -> Void
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Komut veya session ara", text: $query)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($focused)
                        .onSubmit { run(highlighted) }
                        .onKeyPress(.downArrow) { move(1); return .handled }
                        .onKeyPress(.upArrow) { move(-1); return .handled }
                        .onKeyPress(.escape) { close(); return .handled }
                }
                .padding(14)

                Divider().opacity(0.4)

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            Button {
                                run(index)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: entry.symbol).frame(width: 18).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(entry.title).lineLimit(1)
                                        if let subtitle = entry.subtitle {
                                            Text(subtitle).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(index == highlighted ? Theme.surfaceStrong : .clear, in: .rect(cornerRadius: 10))
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 360)
            }
            .frame(width: 560)
            .monsterGlass(cornerRadius: 24, interactive: false)
            .padding(.top, 90)
        }
        .onAppear { focused = true }
        .onChange(of: query) { highlighted = 0 }
    }

    private var entries: [Entry] {
        var all: [Entry] = [
            Entry(id: "new-code", title: String(localized: "Yeni Kod Session'ı"), subtitle: "⌘N", symbol: "plus") {
                window.newSessionMode = .code
                window.showNewSession = true
            },
            Entry(id: "new-chat", title: String(localized: "Yeni Sohbet"), subtitle: "⇧⌘N", symbol: "bubble.left") {
                window.newSessionMode = .chat
                window.showNewSession = true
            },
            Entry(id: "refresh", title: String(localized: "Terminal geçmişini yenile"), subtitle: nil, symbol: "arrow.clockwise") {
                Task { await model.refreshHistory() }
            },
        ]
        for record in model.records {
            all.append(Entry(id: "r-\(record.id)", title: record.title, subtitle: record.projectPath.map(AppModel.abbreviate),
                             symbol: record.mode == .chat ? "bubble.left" : "chevron.left.forwardslash.chevron.right") {
                window.selection = .record(record.id)
            })
        }
        for entry in model.terminalEntries.prefix(50) {
            all.append(Entry(id: "t-\(entry.sessionId)", title: entry.title, subtitle: entry.projectPath.map(AppModel.abbreviate),
                             symbol: "terminal") {
                window.selection = .terminal(entry.sessionId)
            })
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { $0.title.localizedStandardContains(q) || ($0.subtitle?.localizedStandardContains(q) ?? false) }
    }

    private func move(_ delta: Int) {
        let count = entries.count
        guard count > 0 else { return }
        highlighted = (highlighted + delta + count) % count
    }

    private func run(_ index: Int) {
        let list = entries
        guard list.indices.contains(index) else { return }
        close()
        list[index].action()
    }

    private func close() {
        window.showPalette = false
    }
}
