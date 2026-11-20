#if os(macOS)
import AppKit
import SwiftUI
@preconcurrency import WebKit

// The Mac's browser, and the Mac's alone.
//
// iOS and iPadOS hand a page to `SFSafariViewController`, which brings Safari's sessions, Reader,
// AutoFill, and content blockers with it. macOS has no equivalent to present, so the Mac keeps a
// web view it drives itself — with the navigation policy, the classified failures, and the way back
// to the document that come with driving it. The three platforms differ here deliberately: each
// takes the best component it has rather than the one the others could also run.

func isExactAboutBlankURL(_ url: URL) -> Bool {
    url.absoluteString == "about:blank"
}

struct ArchiveBrowserView: View {
    @State private var session: ArchiveBrowserSession
    /// Nothing where there is no document behind the page — a bookmark is its page.
    let onClose: (() -> Void)?

    init(url: URL, onClose: (() -> Void)?) {
        _session = State(initialValue: ArchiveBrowserSession(url: url))
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            // Four controls, and the way back to the document where there is one. No address and no
            // page title: this is a reader looking at what a document pointed at, not a browser
            // being driven — the address was never typed here and cannot be. What the page calls
            // itself is the page's own claim; the window keeps the archive's name for the file,
            // which is the name the reader gave it.
            HStack(spacing: 12) {
                Button("Back", systemImage: "chevron.left") { session.goBack() }
                    .disabled(!session.canGoBack)
                    .help("Back")
                Button("Forward", systemImage: "chevron.right") { session.goForward() }
                    .disabled(!session.canGoForward)
                    .help("Forward")
                if session.isLoading {
                    Button("Stop", systemImage: "xmark") { session.stopLoading() }
                        .help("Stop")
                } else {
                    Button("Reload", systemImage: "arrow.clockwise") { session.reload() }
                        .help("Reload")
                }

                Spacer(minLength: 12)

                Button("Open in Browser", systemImage: "safari") {
                    if let url = session.currentURL { openOutsideArchiveLeaf(url) }
                }
                .help("Open in Browser")
                if let onClose {
                    Button("Back to Document", systemImage: "doc.text") { onClose() }
                        .help("Back to Document")
                }
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .padding(10)
            .background(.bar)

            Divider()
            ZStack {
                ArchiveWebView(session: session)
                if let failure = session.failure {
                    ContentUnavailableView {
                        Label("Page Couldn’t Be Loaded", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(failure.message)
                    } actions: {
                        HStack {
                            Button("Try Again", systemImage: "arrow.clockwise") {
                                session.retry()
                            }
                            Button("Open in Browser", systemImage: "safari") {
                                if let url = session.currentURL { openOutsideArchiveLeaf(url) }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
                }
            }
        }
        .confirmationDialog(
            session.pendingExternalRequest?.title ?? "Open Outside ArchiveLeaf?",
            isPresented: Binding(
                get: { session.pendingExternalRequest != nil },
                set: { if !$0 { session.pendingExternalRequest = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Open", role: .destructive) {
                if let request = session.pendingExternalRequest {
                    openOutsideArchiveLeaf(request.url)
                }
                session.pendingExternalRequest = nil
            }
            Button("Cancel", role: .cancel) { session.pendingExternalRequest = nil }
        } message: {
            Text(session.pendingExternalRequest?.message ?? "")
        }
    }
}

@MainActor
@Observable
final class ArchiveBrowserSession: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    private(set) var currentURL: URL?
    private(set) var failure: ArchiveBrowserFailure?
    var pendingExternalRequest: ArchiveExternalOpenRequest?

    init(url: URL) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        currentURL = url
        super.init()
        webView.navigationDelegate = self
        // Pinch to zoom the page, as `SFSafariViewController` gives iOS and iPadOS for free. This
        // is the page magnified, not the text resized: the layout is untouched and the whole page
        // grows, which is what a reader means when they pinch. WebKit owns the gesture; the Mac
        // only has to stop declining it.
        webView.allowsMagnification = true
        if ProcessInfo.processInfo.environment["ARCHIVELEAF_UI_TEST_BROWSER_FAILURE"] == "1" {
            failure = ArchiveBrowserFailure(error: NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorCannotConnectToHost
            ))
        } else {
            webView.load(URLRequest(url: url))
        }
        refreshState()
    }

    func goBack() { failure = nil; webView.goBack(); refreshState() }
    func goForward() { failure = nil; webView.goForward(); refreshState() }
    func reload() { retry() }
    func stopLoading() { webView.stopLoading(); refreshState() }

    func retry() {
        failure = nil
        guard let currentURL else { return }
        webView.load(URLRequest(url: currentURL))
        refreshState()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
        refreshState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) {
        refreshState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        refreshState()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: any Error
    ) {
        recordFailure(error)
        refreshState()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        guard !isExactAboutBlankURL(url) else {
            decisionHandler(.cancel)
            return
        }
        if ArchiveURLHandler().canOpenInApp(url) {
            if navigationAction.targetFrame?.isMainFrame != false {
                failure = nil
            }
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        } else {
            pendingExternalRequest = ArchiveExternalOpenRequest(
                url: url,
                reason: .unsupportedScheme
            )
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
            if let url = navigationResponse.response.url {
                pendingExternalRequest = ArchiveExternalOpenRequest(
                    url: url,
                    reason: .unsupportedContent
                )
            }
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: any Error
    ) {
        recordFailure(error)
        refreshState()
    }

    private func recordFailure(_ error: any Error) {
        guard let failure = ArchiveBrowserFailure(error: error) else { return }
        self.failure = failure
    }

    private func refreshState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        currentURL = webView.url ?? currentURL
    }
}

struct ArchiveBrowserFailure: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case offline
        case timedOut
        case hostUnavailable
        case other
    }

    let kind: Kind
    let message: String

    init?(error: any Error) {
        let error = error as NSError
        guard !(error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) else {
            return nil
        }

        switch (error.domain, error.code) {
        case (NSURLErrorDomain, NSURLErrorNotConnectedToInternet),
             (NSURLErrorDomain, NSURLErrorNetworkConnectionLost):
            kind = .offline
            message = "Check your internet connection and try again."
        case (NSURLErrorDomain, NSURLErrorTimedOut):
            kind = .timedOut
            message = "The page took too long to respond. Try again or open it in your default browser."
        case (NSURLErrorDomain, NSURLErrorCannotFindHost),
             (NSURLErrorDomain, NSURLErrorCannotConnectToHost),
             (NSURLErrorDomain, NSURLErrorDNSLookupFailed):
            kind = .hostUnavailable
            message = "The website could not be reached. Check the address or open it in your default browser."
        default:
            kind = .other
            message = "ArchiveLeaf could not display this page. Try again or open it in your default browser."
        }
    }
}

struct ArchiveExternalOpenRequest: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        case unsupportedScheme
        case unsupportedContent
    }

    let url: URL
    let reason: Reason

    var title: String {
        switch reason {
        case .unsupportedScheme: "Open Outside ArchiveLeaf?"
        case .unsupportedContent: "Open This Content in Browser?"
        }
    }

    var message: String {
        switch reason {
        case .unsupportedScheme:
            url.absoluteString
        case .unsupportedContent:
            "ArchiveLeaf can’t display this type of content.\n\(url.absoluteString)"
        }
    }
}

private struct ArchiveWebView: NSViewRepresentable {
    let session: ArchiveBrowserSession

    func makeNSView(context: Context) -> WKWebView { session.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
