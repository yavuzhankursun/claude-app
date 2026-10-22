import Foundation

/// CLI'ın `initialize` cevabındaki komut (yerleşik komutlar, skill'ler, eklenti komutları).
/// Slash komutları stdin'e düz metin olarak gönderilir; CLI onları kendisi çalıştırır (spike 2026-10-22: `/context`).
public struct SlashCommand: Sendable, Hashable, Identifiable {
    public var name: String
    public var description: String
    public var argumentHint: String
    public var aliases: [String]
    public var isBuiltin: Bool

    public var id: String { name }

    public init(name: String, description: String, argumentHint: String, aliases: [String], isBuiltin: Bool) {
        self.name = name
        self.description = description
        self.argumentHint = argumentHint
        self.aliases = aliases
        self.isBuiltin = isBuiltin
    }

    /// `initialize` cevabının `commands` dizisi; adı olmayan ve `__` ile başlayan iç komutlar
    /// (ör. `__remote-workflow`, yalnızca sunucu tarafından başlatılan session'lar için) atlanır.
    static func list(from payload: JSONValue?) -> [SlashCommand]? {
        guard let items = payload?["commands"]?.arrayValue else { return nil }
        return items.compactMap { item in
            guard let name = item["name"]?.stringValue, !name.isEmpty, !name.hasPrefix("__") else { return nil }
            return SlashCommand(
                name: name,
                description: HTMLEntities.decode(item["description"]?.stringValue ?? ""),
                argumentHint: item["argumentHint"]?.stringValue ?? "",
                aliases: item["aliases"]?.arrayValue?.compactMap(\.stringValue) ?? [],
                isBuiltin: item["builtin"]?.boolValue ?? false
            )
        }
    }
}

public enum SlashCommandSearch {
    /// Taslak yalnızca "/ad" iken (boşluk yok) öneri verir; aksi halde `nil` (öneri paneli kapalı).
    /// Sıra: ad/alias öneki → ad alanı sonrası (`design:ux…`) öneki → adda geçen → açıklamada geçen; grup içinde alfabetik.
    public static func suggestions(for draft: String, in commands: [SlashCommand], limit: Int = 8) -> [SlashCommand]? {
        guard draft.hasPrefix("/"), !draft.contains(where: \.isWhitespace) else { return nil }
        let query = draft.dropFirst().lowercased()
        guard !query.isEmpty else { return Array(commands.sorted { $0.name < $1.name }.prefix(limit)) }

        func rank(_ command: SlashCommand) -> Int? {
            let names = ([command.name] + command.aliases).map { $0.lowercased() }
            if names.contains(where: { $0.hasPrefix(query) }) { return 0 }
            if names.contains(where: { $0.split(separator: ":").last?.hasPrefix(query) == true }) { return 1 }
            if names.contains(where: { $0.contains(query) }) { return 2 }
            if command.description.lowercased().contains(query) { return 3 }
            return nil
        }
        let ranked = commands.compactMap { command in rank(command).map { (command, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.name < $1.0.name }
        return Array(ranked.prefix(limit).map(\.0))
    }

    public static func completion(_ command: SlashCommand) -> String { "/\(command.name) " }
}

enum HTMLEntities {
    private static let table = ["&gt;": ">", "&lt;": "<", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&amp;": "&"]

    /// CLI açıklamaları HTML kaçışlı gelebiliyor (`-&gt;`). `&amp;` en son çözülür ki `&amp;gt;` iki kez çözülmesin.
    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        for (entity, value) in table where entity != "&amp;" {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }
}
