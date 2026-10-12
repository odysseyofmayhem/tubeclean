import XCTest
@testable import TubeClean

final class NavigationPolicyTests: XCTestCase {
    private func u(_ s: String) -> URL { URL(string: s)! }

    func testMobileSiteGoesToDesktop() {
        XCTAssertEqual(NavigationPolicy.decide(u("https://m.youtube.com/"), isMainFrame: true),
                       .redirect(u("https://www.youtube.com/?app=desktop")))
        XCTAssertEqual(NavigationPolicy.decide(u("https://m.youtube.com/watch?v=abc&app=m"), isMainFrame: true),
                       .redirect(u("https://www.youtube.com/watch?v=abc&app=desktop")))
    }

    func testYouTubeAllowed() {
        XCTAssertEqual(NavigationPolicy.decide(u("https://www.youtube.com/watch?v=abc"), isMainFrame: true), .allow)
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

    func testRestOfGoogleBlocked() {
        for s in ["https://myaccount.google.com/", "https://www.google.com/search?q=x",
                  "https://www.google.com/amp/s/example.com", "https://sites.google.com/view/x",
                  "https://mail.google.com/", "https://google.co.com/", "https://accounts.google.evil.com/",
                  "https://accounts.google.co.com.evil/", "https://accounts.google.co.de/", "https://www.youtube.com/redirect?q=https://example.com"] {
            XCTAssertEqual(NavigationPolicy.decide(u(s), isMainFrame: true), .block, s)
        }
    }

    func testSubframes() {
        XCTAssertEqual(NavigationPolicy.decide(u("https://example.com/frame"), isMainFrame: false), .block)
        XCTAssertEqual(NavigationPolicy.decide(u("https://www.google.com/amp/s/example.com"), isMainFrame: false), .block)
        XCTAssertEqual(NavigationPolicy.decide(u("https://www.youtube.com/embed/x"), isMainFrame: false), .allow)
        XCTAssertEqual(NavigationPolicy.decide(u("https://www.google.com/recaptcha/api2/anchor"), isMainFrame: false), .allow)
        XCTAssertEqual(NavigationPolicy.decide(u("https://www.gstatic.com/x.js"), isMainFrame: false), .allow)
        XCTAssertEqual(NavigationPolicy.decide(u("about:blank"), isMainFrame: false), .allow)
    }

    func testInlineSchemesInMainFrame() {
        XCTAssertEqual(NavigationPolicy.decide(u("about:blank"), isMainFrame: true), .block)
        XCTAssertEqual(NavigationPolicy.decide(u("data:text/html,hi"), isMainFrame: true), .block)
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

    func testRejectsFarFutureVersion() {
        let now = Date(timeIntervalSince1970: 1_791_763_200) // 2026-10-12 00:00 UTC
        XCTAssertNotNil(RulesStore.parse("/* tubeclean-rules version=202610122300 */\n", now: now))
        XCTAssertNil(RulesStore.parse("/* tubeclean-rules version=202610140000 */\n", now: now))
        XCTAssertNil(RulesStore.parse("/* tubeclean-rules version=999999999999999999 */\n", now: now))
        XCTAssertNil(RulesStore.parse("/* tubeclean-rules version=202610129999 */\n", now: now))
        XCTAssertNil(RulesStore.parse("var x; /* tubeclean-rules version=202610120000 */\n", now: now))
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
