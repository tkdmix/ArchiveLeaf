import XCTest
@testable import ArchiveLeaf

final class ArchiveURLHandlingTests: XCTestCase {
    func testOnlyHTTPAndHTTPSOpenInsideArchiveLeaf() throws {
        let handler = ArchiveURLHandler()

        XCTAssertTrue(handler.canOpenInApp(try XCTUnwrap(URL(string: "https://example.com/path"))))
        XCTAssertTrue(handler.canOpenInApp(try XCTUnwrap(URL(string: "http://example.com"))))
        XCTAssertFalse(handler.canOpenInApp(try XCTUnwrap(URL(string: "mailto:test@example.com"))))
        XCTAssertFalse(handler.canOpenInApp(try XCTUnwrap(URL(string: "file:///tmp/note"))))
    }

    #if os(macOS)
    // The browser ArchiveLeaf drives itself is the Mac's. iOS hands its pages to Safari, which
    // answers for navigation and failure on that side and exposes neither to be tested.
    func testOnlyExactAboutBlankIsSilentlyCancelledInBrowserNavigation() throws {
        XCTAssertTrue(isExactAboutBlankURL(try XCTUnwrap(URL(string: "about:blank"))))
        XCTAssertFalse(isExactAboutBlankURL(try XCTUnwrap(URL(string: "about:blank#fragment"))))
        XCTAssertFalse(isExactAboutBlankURL(try XCTUnwrap(URL(string: "about:config"))))
    }
    #endif

    func testLinkifierRequiresAnExplicitCompleteScheme() throws {
        let linkifier = CompleteURLLinkifier()

        XCTAssertEqual(
            linkifier.completeURL(from: "https://example.com/path"),
            URL(string: "https://example.com/path")
        )
        XCTAssertNil(linkifier.completeURL(from: "example.com"))
        XCTAssertNil(linkifier.completeURL(from: "www.example.com"))
        XCTAssertNil(linkifier.completeURL(from: "/local/path"))
        XCTAssertNil(linkifier.completeURL(from: " https://example.com "))
    }

    func testLinkifierDoesNotLinkBareDomainsInsideText() {
        let linked = CompleteURLLinkifier().linkedText(
            "Bare example.com and complete https://example.com/path"
        )
        let links = linked.runs.compactMap(\.link)

        XCTAssertEqual(links, [URL(string: "https://example.com/path")])
    }

    func testJSONLinksOnlyCompleteStringValues() {
        let linked = CompleteURLLinkifier().linkedJSONValues(
            """
            {
              "https://key.example": "https://value.example/path",
              "partial": "See https://ignored.example",
              "bare": "example.com"
            }
            """
        )

        XCTAssertEqual(
            linked.runs.compactMap(\.link),
            [URL(string: "https://value.example/path")]
        )
    }

    #if os(macOS)
    func testBrowserFailureIgnoresNavigationCancellation() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)

        XCTAssertNil(ArchiveBrowserFailure(error: error))
    }

    func testBrowserFailureClassifiesUsefulNetworkStates() throws {
        let offline = try XCTUnwrap(ArchiveBrowserFailure(error: NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet
        )))
        let timeout = try XCTUnwrap(ArchiveBrowserFailure(error: NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut
        )))
        let missingHost = try XCTUnwrap(ArchiveBrowserFailure(error: NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotFindHost
        )))

        XCTAssertEqual(offline.kind, .offline)
        XCTAssertEqual(timeout.kind, .timedOut)
        XCTAssertEqual(missingHost.kind, .hostUnavailable)
    }

    @MainActor
    func testBrowserSessionDoesNotEraseFailureWhenWebKitAlsoReportsCancellation() throws {
        let url = try XCTUnwrap(URL(string: "https://127.0.0.1:1/"))
        let session = ArchiveBrowserSession(url: url)
        session.stopLoading()

        session.webView(
            session.webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        )
        session.webView(
            session.webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        )

        XCTAssertEqual(session.failure?.kind, .hostUnavailable)
    }

    func testUnsupportedContentExplainsExternalBrowserFallback() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/archive.bin"))
        let request = ArchiveExternalOpenRequest(url: url, reason: .unsupportedContent)

        XCTAssertEqual(request.title, "Open This Content in Browser?")
        XCTAssertTrue(request.message.contains("can’t display this type of content"))
        XCTAssertTrue(request.message.contains(url.absoluteString))
    }
    #endif
}
