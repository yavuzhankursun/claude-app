import MonsterCore
import SwiftUI

/// CLI'dan gelen `can_use_tool` isteği için glass onay kartı (US-4).
/// İzin ver ⌘↩ · Bu session için ⌥⌘↩ · Reddet ⌘⌫. Düz ↩ bilerek atanmadı: yazarken yanlışlıkla onay olmasın.
struct PermissionCard: View {
    let request: PermissionRequest
    let decide: (PermissionDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: ToolKind(name: request.toolName).symbolName)
                    .font(.title3)
                    .foregroundStyle(Theme.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude \(request.displayName) kullanmak istiyor")
                        .font(.headline)
                    if let description = request.description, !description.isEmpty {
                        Text(description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }

            preview
                .frame(maxHeight: 220)

            HStack(spacing: 10) {
                Button(role: .destructive) {
                    decide(.deny(message: String(localized: "Kullanıcı Monster'da reddetti.")))
                } label: {
                    Text("Reddet")
                }
                .keyboardShortcut(.delete, modifiers: .command)

                Spacer()

                if !request.suggestions.isEmpty {
                    Button("Bu session için") { decide(.allowForSession) }
                        .keyboardShortcut(.return, modifiers: [.command, .option])
                        .help(sessionHelp)
                }

                Button("İzin ver") { decide(.allowOnce) }
                    .buttonStyle(.monsterGlassProminent)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .buttonStyle(.monsterGlass)
            .controlSize(.large)
        }
        .padding(16)
        .monsterGlass(cornerRadius: 24, tint: Theme.warning.opacity(0.10), interactive: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("İzin isteği: \(request.displayName)"))
    }

    @ViewBuilder
    private var preview: some View {
        if let diff = LineDiff.fileDiff(toolName: request.toolName, input: request.input) {
            DiffView(diff: diff)
        } else if let command = request.input["command"]?.stringValue {
            CodeBlockView(code: command, language: "bash")
        } else {
            ScrollView {
                CodeBlockView(code: request.input.prettyString(), language: "json")
            }
        }
    }

    /// Öneriler CLI'dan gelir (ör. "acceptEdits moduna geç", "Bash(git *) kuralını ekle").
    private var sessionHelp: String {
        let parts = request.suggestions.compactMap { suggestion -> String? in
            switch suggestion["type"]?.stringValue {
            case "setMode": return suggestion["mode"]?.stringValue.map { "mode → \($0)" }
            case "addRules":
                return suggestion["rules"]?.arrayValue?.compactMap { rule in
                    let tool = rule["toolName"]?.stringValue ?? ""
                    let content = rule["ruleContent"]?.stringValue
                    return content.map { "\(tool)(\($0))" } ?? tool
                }.joined(separator: ", ")
            default: return suggestion["type"]?.stringValue
            }
        }
        return parts.joined(separator: " · ")
    }
}
