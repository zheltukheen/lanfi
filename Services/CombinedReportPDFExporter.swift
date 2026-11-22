import Foundation
import WebKit

/// Renders the combined report to PDF with the same HTML the browser export
/// uses, so both handover documents stay identical.
@MainActor
enum CombinedReportPDFExporter {
    static func pdf(for report: CombinedReport) async throws -> Data {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 794, height: 1123))
        let waiter = NavigationWaiter()
        webView.navigationDelegate = waiter
        async let loaded: Void = waiter.wait()
        webView.loadHTMLString(CombinedReportExporter.html(for: report), baseURL: nil)
        try await loaded
        return try await webView.pdf()
    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func wait() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(
        _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
