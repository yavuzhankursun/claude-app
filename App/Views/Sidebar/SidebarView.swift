import MonsterCore
import SwiftUI

/// Projelere göre gruplu session listesi (US-1). Kenar çubuğu macOS 26'da sistem tarafından Liquid Glass olarak çizilir.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Bindable var window: WindowState

    var body: some View {
        List(selection: $window.selection) {
            ForEach(model.sections(matching: window.sidebarQuery)) { section in
                Section {
                    ForEach(section.records) { record in
                        SessionRow(record: record, controller: model.liveController(id: record.id))
                            .tag(SidebarSelection.record(record.id))
                            .contextMenu {
                                Button("Sil", role: .destructive) { Task { await model.delete(record) } }
                            }
                    }
                    ForEach(section.terminal) { entry in
                        TerminalSessionRow(entry: entry)
                            .tag(SidebarSelection.terminal(entry.sessionId))
                    }
                } header: {
                    SectionHeader(title: section.title, subtitle: section.subtitle)
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $window.sidebarQuery, placement: .sidebar, prompt: Text("Session ara"))
        .overlay {
            if model.records.isEmpty && model.terminalEntries.isEmpty && !model.isRefreshingHistory {
                ContentUnavailableView("Henüz session yok", systemImage: "tray",
                                       description: Text("⌘N ile yeni bir session başlatın."))
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    window.newSessionMode = .code
                    window.showNewSession = true
                } label: {
                    Label("Yeni session", systemImage: "square.and.pencil")
                }
                .help("Yeni session (⌘N)")
            }
        }
        .refreshable { await model.refreshHistory() }
        .task {
            // Terminalde açılan yeni session'lar için hafif, periyodik yenileme.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                await model.refreshHistory()
            }
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
    }
}

struct SessionRow: View {
    let record: SessionRecord
    let controller: SessionController?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: record.mode == .chat ? "bubble.left" : "chevron.left.forwardslash.chevron.right")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .lineLimit(1)
                Text(record.lastActiveAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            if record.mode == .code && record.permissionMode == .fullAccess {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(Theme.danger)
                    .help("Full access")
            }
            if let controller {
                LiveIndicator(controller: controller)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Çalışan session için canlı gösterge; izin bekleniyorsa turuncu.
struct LiveIndicator: View {
    let controller: SessionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if controller.pendingPermission != nil {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
                .symbolEffect(.pulse, options: .repeat(.continuous), isActive: !reduceMotion)
                .accessibilityLabel("İzin bekleniyor")
        } else if controller.isTurnActive {
            Circle()
                .fill(.tint)
                .frame(width: 7, height: 7)
                .phaseAnimator([0.35, 1.0]) { dot, opacity in dot.opacity(reduceMotion ? 1 : opacity) }
                    animation: { _ in .easeInOut(duration: 0.7) }
                .accessibilityLabel("Çalışıyor")
        }
    }
}

struct TerminalSessionRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(.tertiary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(entry.lastModified, format: .relative(presentation: .named))
                    if let branch = entry.gitBranch, !branch.isEmpty {
                        Text("· \(branch)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .help("Terminal session'ı — seçince --resume ile devam eder")
    }
}
