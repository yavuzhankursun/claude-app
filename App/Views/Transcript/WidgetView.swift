import MonsterCore
import SwiftUI
import WebKit

/// Claude'un ürettiği SVG/HTML'i sandbox'lı bir WKWebView'da çizer (US-6, THREAT_MODEL T-3).
/// Katmanlar: (1) CSP `default-src 'none'` (2) sayfa JavaScript'i kapalı (3) kalıcı olmayan veri deposu
/// (4) ilk yükleme dışındaki tüm gezinmeler reddedilir (5) baseURL yok → file:// erişimi yok.
struct WidgetView: View {
    let kind: WidgetKind
    let source: String
    @State private var height: CGFloat = 120

    var body: some View {
        SandboxedWebView(html: WidgetDocument.html(for: kind, source: source, dark: true), height: $height)
            .frame(height: min(max(height, 40), 900))
            .frame(maxWidth: .infinity)
            .padding(10)
            .surface()
            .accessibilityLabel(kind == .svg ? "SVG görseli" : "HTML görseli")
    }
}

struct SandboxedWebView: NSViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isFraudulentWebsiteWarningEnabled = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        context.coordinator.load(html, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedHTML != html {
            context.coordinator.load(html, in: webView)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var height: Binding<CGFloat>
        var loadedHTML: String?
        private var allowNextNavigation = false

        init(height: Binding<CGFloat>) {
            self.height = height
        }

        func load(_ html: String, in webView: WKWebView) {
            loadedHTML = html
            allowNextNavigation = true
            webView.loadHTMLString(html, baseURL: nil)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            // Yalnızca bizim başlattığımız about:blank yüklemesi; link tıklamaları ve yönlendirmeler reddedilir.
            if allowNextNavigation, navigationAction.navigationType == .other, navigationAction.request.url?.scheme == "about" {
                allowNextNavigation = false
                return .allow
            }
            return .cancel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Uygulama tarafından enjekte edilen ölçüm; sayfa betikleri kapalı kalır.
            Task { [weak self] in
                guard let number = try? await webView.evaluateJavaScript("Math.ceil(document.documentElement.scrollHeight)")
                    as? NSNumber else { return }
                self?.height.wrappedValue = CGFloat(truncating: number)
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil
        }
    }
}
