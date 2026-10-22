import Foundation

/// Claude çıktısındaki SVG/HTML güvenilmez girdidir. WebView'a verilmeden önce sıkı bir CSP ile sarılır:
/// betik yok, ağ yok, form yok, iframe yok; yalnızca satır içi stil ve data: görseller.
/// WebView tarafında ayrıca JavaScript kapatılır ve tüm gezinmeler reddedilir (iki katmanlı savunma).
public enum WidgetDocument {
    public static let contentSecurityPolicy =
        "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:; "
        + "script-src 'none'; connect-src 'none'; frame-src 'none'; child-src 'none'; "
        + "form-action 'none'; base-uri 'none'; object-src 'none'; media-src 'none'"

    /// Yerleştirmeden önce açıkça tehlikeli etiketleri metinden ayıklar. CSP birincil korumadır; bu ikinci katman.
    static let strippedTagNames = ["script", "iframe", "object", "embed", "link", "meta", "base", "form", "foreignObject"]

    public static func html(for kind: WidgetKind, source: String, dark: Bool) -> String {
        let body = sanitize(source)
        let fg = dark ? "#EDEDF2" : "#111114"
        return """
        <!doctype html>
        <html><head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <style>
          :root { color-scheme: \(dark ? "dark" : "light"); }
          html, body { margin: 0; padding: 0; background: transparent; color: \(fg);
                       font: 13px -apple-system, system-ui, sans-serif; overflow: hidden; }
          body > svg, body > * { max-width: 100%; height: auto; display: block; }
        </style>
        </head><body>\(body)</body></html>
        """
    }

    static func sanitize(_ source: String) -> String {
        var s = source
        for tag in strippedTagNames {
            // <tag ...>...</tag> ve kendiliğinden kapanan <tag .../>
            let paired = "<\\s*\(tag)\\b[^>]*>[\\s\\S]*?<\\s*/\\s*\(tag)\\s*>"
            let single = "<\\s*/?\\s*\(tag)\\b[^>]*>"
            s = s.replacingOccurrences(of: paired, with: "", options: [.regularExpression, .caseInsensitive])
            s = s.replacingOccurrences(of: single, with: "", options: [.regularExpression, .caseInsensitive])
        }
        // on* olay öznitelikleri ve javascript: URL'leri
        s = s.replacingOccurrences(of: "\\son[a-z]+\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)", with: "",
                                   options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "(href|src|xlink:href)\\s*=\\s*(\"|')\\s*(javascript|https?|file|ftp):[^\"']*(\"|')",
                                   with: "", options: [.regularExpression, .caseInsensitive])
        return s
    }
}
