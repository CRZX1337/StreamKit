import Foundation
import UIKit
import WebKit

@MainActor
final class OverlayManager: NSObject, ObservableObject {
    enum OverlayError: LocalizedError {
        case invalidURL

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Overlay URL is invalid."
            }
        }
    }

    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var currentURL: URL?

    let webView: WKWebView

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let userContentController = WKUserContentController()
        configuration.userContentController = userContentController

        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.configuration.preferences.setValue(60, forKey: "preferredFramesPerSecond")
    }

    func loadOverlay(from urlString: String) throws {
        guard let url = URL(string: urlString) else {
            throw OverlayError.invalidURL
        }
        lastError = nil
        currentURL = url
        isLoading = true
        webView.load(URLRequest(url: url))
    }

    func loadOverlay(from url: URL) {
        lastError = nil
        currentURL = url
        isLoading = true
        webView.load(URLRequest(url: url))
    }

    func reload() {
        webView.reload()
    }

    func evaluateJavaScript(_ script: String) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }
}

extension OverlayManager: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.isLoading = false
            self.lastError = nil
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        Task { @MainActor in
            self.isLoading = false
            self.lastError = error.localizedDescription
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        Task { @MainActor in
            self.isLoading = false
            self.lastError = error.localizedDescription
        }
    }
}
