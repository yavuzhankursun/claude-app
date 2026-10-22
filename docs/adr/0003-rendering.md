# ADR-0003 — Render: native Markdown, bağımlılıksız vurgulama, sandbox'lı widget

**Durum:** Kabul · **Tarih:** 2026-10-22

## Karar
- **Markdown:** Blok ayrımı `MonsterCore.MarkdownParser` (başlık, paragraf, liste, alıntı, tablo, çitli kod, kural);
  satır içi biçim `AttributedString(markdown:, .inlineOnlyPreservingWhitespace)`. Akış sırasında kapanmamış kod çiti
  kod olarak gösterilir.
- **Kod vurgulama:** `SyntaxHighlighter` — sözcüksel, bağımlılıksız; 60 KB üstü bloklar düz metin (kare bütçesi).
- **Diff:** `LineDiff` stdlib `CollectionDifference` (Myers); Edit / MultiEdit / Write girdilerinden; 3 satır bağlam.
- **SVG/HTML widget:** yalnızca *kapanmış* ```` ```svg ```` / ```` ```html ```` çitleri. `WidgetDocument` ile:
  CSP `default-src 'none'; script-src 'none'; connect-src 'none'; img-src data:` + tehlikeli etiket/öznitelik ayıklama;
  `WKWebView`: içerik JS kapalı, `nonPersistent` veri deposu, `baseURL: nil` (file:// yok), ilk `about:blank` dışında
  tüm gezinmeler `.cancel`, yeni pencere yok. Yükseklik ölçümü uygulama tarafından enjekte edilen tek ifadeyle.
- **Performans:** `TranscriptRow: Equatable` + `.equatable()`; `LazyVStack`; `defaultScrollAnchor(.bottom, for: .sizeChanges)`;
  SessionController olayları ≤60 Hz'de yayınlar.

## Neden SwiftUI `WebView` (macOS 26) değil?
`WKWebView` + `NSViewRepresentable` ile her güvenlik ayarı (JS, veri deposu, gezinme kararı) açıkça ve test
edilmiş API'lerle kurulabiliyor. SwiftUI `WebPage` aynı ayarları sunduğunda M3'te geçiş değerlendirilir.
