import XCTest
@testable import TubeClean

final class NavigationPolicyTests: XCTestCase {
    private func u(_ s: String) -> URL { URL(string: s)! }

    func testYouTubeAllowed() {
        XCTAssertEqual(NavigationPolicy.decide(u("https://www.youtube.com/watch?v=abc"), isMainFrame: true), .allow)
        XCTAssertEqual(NavigationPolicy.decide(u("https://m.youtube.com/"), isMainFrame: true), .allow)
        XCTAssertEqual(NavigationPolicy.decide(u("https://www.youtube.com/@SomeChannel/videos"), isMainFrame: true), .allow)
    }

    func testGoogleSignInAllowed() {
        XCTAssertEqual(NavigationPolicy.decide(u("https://accounts.google.com/ServiceLogin"), isMainFrame: true), .allow)
        XCTAssertEqual(NavigationPolicy.decide(u("https://accounts.google.co.uk/x"), isMainFrame: true), .allow)
        XCTAssertEqual(NavigationPolicy.decide(u("https://consent.youtube.com/m"), isMainFrame: true), .allow)
    }

    func testOtherSitesBlocked() {
        XCTAssertEqual(NavigationPolicy.decide(u("https://example.com/"), isMainFrame: true), .block)
        XCTAssertEqual(NavigationPolicy.decide(u("https://youtube.com.evil.example/"), isMainFrame: true), .block)
        XCTAssertEqual(NavigationPolicy.decide(u("https://notyoutube.com/"), isMainFrame: true), .block)
        XCTAssertEqual(NavigationPolicy.decide(u("https://google.evil.example/"), isMainFrame: true), .block)
        XCTAssertEqual(NavigationPolicy.decide(u("mailto:a@b.c"), isMainFrame: true), .block)
    }

    func testSubframesAllowed() {
        XCTAssertEqual(NavigationPolicy.decide(u("https://example.com/frame"), isMainFrame: false), .allow)
    }

    func testShortsRedirectHome() {
        let home = NavigationPolicy.Decision.redirect(NavigationPolicy.home)
        XCTAssertEqual(NavigationPolicy.decide(u("https://www.youtube.com/shorts/abc123"), isMainFrame: true), home)
        XCTAssertEqual(NavigationPolicy.decide(u("https://www.youtube.com/feed/shorts"), isMainFrame: true), home)
        XCTAssertEqual(NavigationPolicy.decide(u("https://www.youtube.com/@MrBeast/shorts"), isMainFrame: true), home)
        XCTAssertEqual(NavigationPolicy.decide(u("https://www.youtube.com/channel/UCx/shorts"), isMainFrame: true), home)
        // A video whose title mentions shorts is fine.
        XCTAssertEqual(NavigationPolicy.decide(u("https://www.youtube.com/results?search_query=shorts"), isMainFrame: true), .allow)
    }

    func testYoutuBeShortLink() {
        XCTAssertEqual(NavigationPolicy.decide(u("https://youtu.be/dQw4w9WgXcQ"), isMainFrame: true),
                       .redirect(u("https://www.youtube.com/watch?v=dQw4w9WgXcQ")))
    }
}

@MainActor
final class RulesParseTests: XCTestCase {
    func testParsesVersion() {
        let r = RulesStore.parse("/* tubeclean-rules version=202610120300 */\n(()=>{})();")
        XCTAssertEqual(r?.version, 202610120300)
    }

    func testRejectsForeignFile() {
        XCTAssertNil(RulesStore.parse("<html>404</html>"))
        XCTAssertNil(RulesStore.parse(""))
    }

    func testBundledScriptIsValid() throws {
        let bundle = Bundle(for: BrowserController.self)
        let url = try XCTUnwrap(bundle.url(forResource: "tubeclean", withExtension: "js"))
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertNotNil(RulesStore.parse(text))
    }
}
