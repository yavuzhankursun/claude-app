import MonsterCore
import SwiftUI
import UniformTypeIdentifiers

/// Yüzen glass composer. Odaklanınca/metin girilince genişler; gönder düğmesi tur sırasında durdur'a dönüşür.
/// ↩ gönderir, ⇧↩ yeni satır, Esc durdurur. `TextField(axis: .vertical)` içeriğe göre büyür.
///
/// Claude uygulaması eşliği (docs/PARITY.md, composer P1):
/// - `/` ile başlayan taslakta CLI'ın komut listesinden öneriler (↑/↓ seç, ↩/⇥ tamamla, Esc kapat).
/// - Kod modunda `@` ile proje dosyası önerileri; gönderilirken içerik eklenir (`MentionResolver`).
/// - Görsel/dosya ekleme: ataş düğmesi, sürükle-bırak, görsel yapıştırma.
struct ComposerView: View {
    @Bindable var controller: SessionController
    let glassNamespace: Namespace.ID
    @FocusState private var focused: Bool
    @State private var highlighted = 0
    @State private var dismissedDraft: String?
    @State private var showImporter = false
    @State private var isDropTargeted = false
    /// Öneriler yalnızca taslak/komut listesi/dosya indeksi değişince hesaplanır; akış sırasındaki ~60 Hz gövde
    /// yenilemelerinde 20k yol üzerinde bulanık arama tekrarlanmaz (güvenlik/perf incelemesi #4).
    @State private var suggestions: [ComposerSuggestion] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var expanded: Bool { focused || !controller.draft.isEmpty || !controller.attachments.isEmpty }
    private var placeholder: LocalizedStringKey {
        controller.record.mode == .chat ? "Claude'a sorun…" : "Claude Code'a bir görev verin…  (/ komut, @ dosya)"
    }

    private func refreshSuggestions() {
        let draft = controller.draft
        guard dismissedDraft != draft else { suggestions = []; return }
        if let commands = SlashCommandSearch.suggestions(for: draft, in: controller.slashCommands), !commands.isEmpty {
            suggestions = commands.map(ComposerSuggestion.command)
        } else if controller.supportsFileMentions, let query = MentionQuery.active(in: draft), let index = controller.fileIndex {
            suggestions = index.search(query).map(ComposerSuggestion.file)
        } else {
            suggestions = []
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                if !suggestions.isEmpty {
                    SuggestionList(suggestions: suggestions, highlighted: min(highlighted, suggestions.count - 1)) { accept($0) }
                        .transition(.blurReplace)
                }
                if !controller.attachments.isEmpty {
                    AttachmentStrip(controller: controller)
                        .transition(.blurReplace)
                }
                textField
                if expanded {
                    ComposerAccessories(controller: controller) { showImporter = true }
                        .transition(.blurReplace)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .monsterGlass(cornerRadius: expanded ? 22 : 26)
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .allowsHitTesting(false)
                }
            }
            .glassEffectID("composer", in: glassNamespace)
            .dropDestination(for: URL.self) { urls, _ in
                controller.addAttachments(from: urls)
                return !urls.isEmpty
            } isTargeted: { isDropTargeted = $0 }

            sendButton
                .glassEffectID("send", in: glassNamespace)
        }
        .animation(Motion.smooth(reduceMotion), value: expanded)
        .animation(Motion.snap(reduceMotion), value: suggestions.isEmpty)
        .animation(Motion.snap(reduceMotion), value: controller.attachments.count)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { controller.addAttachments(from: urls) }
        }
        .onChange(of: controller.draft) { _, draft in
            highlighted = 0
            if dismissedDraft != nil, dismissedDraft != draft { dismissedDraft = nil }
            if MentionQuery.active(in: draft) != nil { controller.ensureFileIndex() }
            // Komut listesi CLI'ın `initialize` cevabıyla gelir; süreç yoksa ilk "/"ta başlatılır.
            if draft.hasPrefix("/"), controller.slashCommands.isEmpty { Task { await controller.prewarm() } }
            refreshSuggestions()
        }
        .onChange(of: controller.slashCommands.count) { refreshSuggestions() }
        .onChange(of: controller.fileIndex?.paths.count) { refreshSuggestions() }
        .onAppear { focused = true }
    }

    private var textField: some View {
        TextField(placeholder, text: $controller.draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.body)
            .lineLimit(expanded ? 1...10 : 1...1)
            .focused($focused)
            .onSubmit { Task { await controller.send() } }
            .onKeyPress(.return, phases: .down) { press in
                if !suggestions.isEmpty, !press.modifiers.contains(.shift) {
                    accept(suggestions[min(highlighted, suggestions.count - 1)])
                    return .handled
                }
                // ⇧↩ yeni satır; düz ↩ onSubmit'e düşer ve gönderir.
                guard press.modifiers.contains(.shift) else { return .ignored }
                controller.draft += "\n"
                return .handled
            }
            .onKeyPress(.tab) {
                guard !suggestions.isEmpty else { return .ignored }
                accept(suggestions[min(highlighted, suggestions.count - 1)])
                return .handled
            }
            .onKeyPress(.downArrow) {
                guard !suggestions.isEmpty else { return .ignored }
                highlighted = (min(highlighted, suggestions.count - 1) + 1) % suggestions.count
                return .handled
            }
            .onKeyPress(.upArrow) {
                guard !suggestions.isEmpty else { return .ignored }
                highlighted = (min(highlighted, suggestions.count - 1) - 1 + suggestions.count) % suggestions.count
                return .handled
            }
            .onKeyPress(.escape) {
                if !suggestions.isEmpty {
                    dismissedDraft = controller.draft
                    refreshSuggestions()
                    return .handled
                }
                guard controller.isTurnActive else { return .ignored }
                Task { await controller.interrupt() }
                return .handled
            }
            .background(PasteInterceptor(isActive: focused) { pasteboard in pasteAttachments(from: pasteboard) })
            .accessibilityLabel("Mesaj")
    }

    private func accept(_ suggestion: ComposerSuggestion) {
        switch suggestion {
        case .command(let command): controller.draft = SlashCommandSearch.completion(command)
        case .file(let path): controller.draft = MentionQuery.replacingActive(in: controller.draft, with: path)
        }
        highlighted = 0
        refreshSuggestions()
    }

    /// Panoda metin yoksa ve görsel/dosya varsa ek olarak alır (`true` = ⌘V tüketildi). Metin varsa metin alanı yapıştırır.
    private func pasteAttachments(from pasteboard: NSPasteboard) -> Bool {
        guard pasteboard.string(forType: .string) == nil else { return false }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            controller.addAttachments(from: urls)
            return true
        }
        if let data = PasteboardImage.pngData(from: pasteboard) {
            controller.addImage(data: data, name: "yapistirilan-\(controller.attachments.count + 1).png")
            return true
        }
        return false
    }

    @ViewBuilder
    private var sendButton: some View {
        if controller.isTurnActive {
            Button {
                Task { await controller.interrupt() }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.monsterGlass(shape: .circle))
            .help("Durdur (Esc)")
            .accessibilityLabel("Durdur")
        } else {
            Button {
                Task { await controller.send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.monsterGlass(prominent: true, shape: .circle))
            .disabled(!controller.canSend)
            .help("Gönder (↩)")
            .accessibilityLabel("Gönder")
        }
    }
}

enum ComposerSuggestion: Identifiable, Hashable {
    case command(SlashCommand)
    case file(String)

    var id: String {
        switch self {
        case .command(let command): "c:" + command.name
        case .file(let path): "f:" + path
        }
    }
}

private struct SuggestionList: View {
    let suggestions: [ComposerSuggestion]
    let highlighted: Int
    let onSelect: (ComposerSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button { onSelect(suggestion) } label: {
                    row(suggestion)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(index == highlighted ? Theme.surfaceStrong : .clear,
                                    in: .rect(cornerRadius: Theme.smallCorner - 4, style: .continuous))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Öneriler")
    }

    @ViewBuilder
    private func row(_ suggestion: ComposerSuggestion) -> some View {
        switch suggestion {
        case .command(let command):
            HStack(spacing: 8) {
                Text("/" + command.name)
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                if !command.argumentHint.isEmpty {
                    Text(command.argumentHint).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
                Text(command.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
        case .file(let path):
            let url = URL(filePath: path)
            HStack(spacing: 8) {
                Image(systemName: "doc").foregroundStyle(.secondary)
                Text(url.lastPathComponent).font(.callout.weight(.medium)).lineLimit(1)
                Text(url.deletingLastPathComponent().relativePath == "." ? "" : url.deletingLastPathComponent().relativePath)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                Spacer(minLength: 0)
            }
        }
    }
}

/// Eklenen görseller (küçük resim) ve dosyalar; her biri kaldırılabilir.
private struct AttachmentStrip: View {
    let controller: SessionController

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(controller.attachments) { attachment in
                    HStack(spacing: 6) {
                        thumbnail(attachment)
                        Text(attachment.name).font(.caption).lineLimit(1).frame(maxWidth: 160, alignment: .leading)
                        Button {
                            controller.removeAttachment(attachment)
                        } label: {
                            Image(systemName: "xmark").font(.caption2.weight(.bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("\(attachment.name) ekini kaldır"))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.surfaceStrong, in: .rect(cornerRadius: Theme.smallCorner - 4, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ attachment: Attachment) -> some View {
        if case .image = attachment.kind, let image = NSImage(data: attachment.data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 26, height: 26)
                .clipShape(.rect(cornerRadius: 5, style: .continuous))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "doc.text").foregroundStyle(.secondary).accessibilityHidden(true)
        }
    }
}

enum PasteboardImage {
    /// PNG doğrudan; TIFF (ekran görüntüsü kopyalama) PNG'ye çevrilir.
    static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// ⌘V, `TextField`'ın içindeki NSTextView'a gider ve görseli yok sayar; `onPasteCommand` bu yüzden tetiklenmez.
/// Composer odaktayken uygulama içi ⌘V'yi yerel olay izleyicisiyle önce görür; ek alınmazsa olay olduğu gibi geçer.
/// Yalnızca kendi penceresinden gelen olaylara bakar: çoklu pencerede ⌘V iki composer'a birden düşmez
/// (güvenlik incelemesi, hipotez — pencere denetimiyle kapatıldı).
private struct PasteInterceptor: NSViewRepresentable {
    let isActive: Bool
    let handle: (NSPasteboard) -> Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.handle = handle
        if isActive { context.coordinator.install(for: view) } else { context.coordinator.remove() }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.remove() }

    func makeCoordinator() -> Coordinator { Coordinator(handle: handle) }

    @MainActor
    final class Coordinator {
        var handle: (NSPasteboard) -> Bool
        private var monitor: Any?

        init(handle: @escaping (NSPasteboard) -> Bool) { self.handle = handle }

        func install(for view: NSView) {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak view] event in
                guard let self, let window = view?.window, event.window === window else { return event }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard flags == .command, event.charactersIgnoringModifiers?.lowercased() == "v" else { return event }
                return self.handle(.general) ? nil : event
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

/// Composer genişleyince görünen küçük seçiciler: ek düğmesi, mod rozeti, proje adı, ek hatası.
private struct ComposerAccessories: View {
    let controller: SessionController
    let onAttach: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onAttach) {
                Image(systemName: "paperclip").font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Görsel ya da dosya ekle (sürükle-bırak ve yapıştırma da olur)")
            .accessibilityLabel("Ek ekle")
            ModeBadge(mode: controller.record.mode, permission: controller.record.permissionMode)
            if let project = controller.record.projectPath {
                Label(URL(filePath: project).lastPathComponent, systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = controller.attachmentError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .lineLimit(1)
            }
            Spacer()
            Text("⇧↩ yeni satır")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

struct ModeBadge: View {
    let mode: SessionMode
    let permission: PermissionMode

    var body: some View {
        Text(style.text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(style.color)
            .monsterGlass(in: Capsule(), tint: style.color.opacity(0.22), interactive: false)
    }

    private var style: (text: LocalizedStringKey, color: Color) {
        switch (mode, permission) {
        case (.chat, _): ("Sohbet · salt-okunur", .secondary)
        case (.code, .ask): ("Ask", .secondary)
        case (.code, .autoEdit): ("Auto-edit", .primary)
        case (.code, .plan): ("Plan", .primary)
        case (.code, .fullAccess): ("Full access", Theme.danger)
        }
    }
}
