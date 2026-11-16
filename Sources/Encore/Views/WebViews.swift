import SwiftUI
import WebKit

/// Google sign-in sheet. Its web view exists only while the sheet is open; afterwards
/// the cookies are copied to the app and no web page is used at all.
struct WebSheet: View {
    let kind: WebSheetKind
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(Color.brand)
                Text("YouTube Music'te oturum aç")
                    .font(.headline)
                Spacer()
                Button("Kapat") {
                    app.engine.webSheet = nil
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            Divider()
            SheetWebView(kind: kind)
        }
        .frame(width: 920, height: 700)
    }
}

struct SheetWebView: NSViewRepresentable {
    let kind: WebSheetKind

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let kind: WebSheetKind
        private var finished = false
        init(kind: WebSheetKind) { self.kind = kind }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !finished, webView.url?.host == "music.youtube.com" else { return }
            webView.stopLoading()
            finished = true
            Task { @MainActor in YTMusic.shared.loginFinished() }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(kind: kind) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = YTMusic.userAgent
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.load(URLRequest(url: YTMusic.loginURL))
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
