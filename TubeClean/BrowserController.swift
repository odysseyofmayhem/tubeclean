import os
import UIKit
import WebKit

/// Owns the single web view: injects the blocking script, keeps the main
/// frame on YouTube, and turns Shorts links into the home page.
@MainActor
final class BrowserController: NSObject {
    private static let log = Logger(subsystem: "uk.co.ilmaris.tubeclean", category: "browser")

    let rules: RulesStore
    let webView: WKWebView
    private let messages = ScriptMessageProxy()
    private var started = false
    private var recentCrashes: [Date] = []
    #if DEBUG
    private var evalDone = false
    #endif

    init(rules: RulesStore) {
        self.rules = rules

        let config = WKWebViewConfiguration()
        // The default persistent store keeps the Google sign-in between launches.
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Ask for the desktop site, as Safari on iPad does.
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        // Google refuses sign-in from web views whose user agent lacks the
        // Safari suffix ("This browser or app may not be secure").
        config.applicationNameForUserAgent = Self.safariSuffix

        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        #if DEBUG
        webView.isInspectable = true // Safari > Develop on a Mac can attach
        #endif
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic

        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self, weak refresh] _ in
            self?.webView.reload()
            refresh?.endRefreshing()
        }, for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        messages.onMessage = { body in
            let text: String
            if JSONSerialization.isValidJSONObject(body),
               let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
               let s = String(data: data, encoding: .utf8) {
                text = s
            } else {
                text = String(describing: body)
            }
            Self.log.info("page: \(text, privacy: .public)")
        }
        config.userContentController.add(messages, contentWorld: .page, name: "tubeclean")

        installScript(rules.current)
        // A new script takes effect on the next full page load; reloading
        // here would interrupt whatever he is watching.
        rules.onUpdate = { [weak self] new in
            self?.installScript(new)
        }
    }

    /// Stops the script before its first statement on any page that is not
    /// YouTube, so a bad rules file can never run on Google's sign-in pages.
    /// A top-level `throw` aborts the whole script; `throw 0` avoids calling
    /// anything the file could redefine through hoisting.
    static let youTubeOnlyGuard =
        "if (!/^(?:[a-z0-9-]+\\.)*youtube\\.com$/.test(location.hostname)) throw 0;\n"

    /// "Version/27.0 Safari/605.1.15", matching the running iPadOS.
    static var safariSuffix: String {
        let major = UIDevice.current.systemVersion.split(separator: ".").first ?? "27"
        return "Version/\(major).0 Safari/605.1.15"
    }

    func start() async {
        guard !started else { return }
        started = true
        await rejectConsentIfUnset()
        var start = NavigationPolicy.home
        #if DEBUG
        // Test hook: `-TCStartURL <url>` as a launch argument opens that page.
        if let s = UserDefaults.standard.string(forKey: "TCStartURL"), let u = URL(string: s) { start = u }
        #endif
        webView.load(URLRequest(url: start))
        await rules.refreshIfDue()
    }

    /// Sets YouTube's "Reject all" consent cookie on first run so the
    /// "Before you continue" wall never appears. Never overrides a choice.
    private func rejectConsentIfUnset() async {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let cookies = await store.allCookies()
        guard !cookies.contains(where: { $0.name == "SOCS" && $0.domain.hasSuffix("youtube.com") }) else { return }
        let props: [HTTPCookiePropertyKey: Any] = [
            .name: "SOCS", .value: "CAI", .domain: ".youtube.com", .path: "/", .secure: true,
            .expires: Date().addingTimeInterval(390 * 24 * 60 * 60),
        ]
        if let cookie = HTTPCookie(properties: props) {
            await store.setCookie(cookie)
        }
    }

    private func installScript(_ rules: RulesStore.Rules) {
        let ucc = webView.configuration.userContentController
        ucc.removeAllUserScripts()
        #if DEBUG
        // Test hook: `-TCNoRules YES` runs without the blocking script.
        if UserDefaults.standard.bool(forKey: "TCNoRules") { return }
        #endif
        guard !rules.source.isEmpty else { return }
        ucc.addUserScript(WKUserScript(
            source: Self.youTubeOnlyGuard + rules.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .page
        ))
        Self.log.info("installed rules version \(rules.version)")
    }
}

extension BrowserController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences
    ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        guard let url = navigationAction.request.url else { return (.cancel, preferences) }
        let isMain = navigationAction.targetFrame?.isMainFrame ?? true
        switch NavigationPolicy.decide(url, isMainFrame: isMain) {
        case .allow:
            return (.allow, preferences)
        case .redirect(let target):
            Self.log.info("redirect \(url.absoluteString, privacy: .public) -> \(target.absoluteString, privacy: .public)")
            webView.load(URLRequest(url: target))
            return (.cancel, preferences)
        case .block:
            Self.log.info("blocked \(url.absoluteString, privacy: .public)")
            return (.cancel, preferences)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // iPadOS kills the web process under memory pressure; come back.
        // If it keeps crashing, or nothing had loaded yet, start from home.
        let now = Date()
        recentCrashes = recentCrashes.filter { now.timeIntervalSince($0) < 10 } + [now]
        Self.log.error("web process ended (\(self.recentCrashes.count) in 10 s)")
        if webView.url == nil || recentCrashes.count > 1 {
            webView.load(URLRequest(url: NavigationPolicy.home))
        } else {
            webView.reload()
        }
    }

    #if DEBUG
    /// Test hook: `-TCEvalJS <base64 js>` runs once after the first page
    /// loads, and logs the result. Debug builds only.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !evalDone,
              let b64 = UserDefaults.standard.string(forKey: "TCEvalJS"),
              let data = Data(base64Encoded: b64),
              let js = String(data: data, encoding: .utf8) else { return }
        evalDone = true
        Self.log.info("eval scheduled on \(webView.url?.absoluteString ?? "-", privacy: .public)")
        Task {
            try? await Task.sleep(for: .seconds(4))
            do {
                let result = try await webView.evaluateJavaScript(js)
                Self.log.info("eval: \(String(describing: result), privacy: .public)")
            } catch {
                Self.log.error("eval failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    #endif
}

extension BrowserController: WKUIDelegate {
    /// Links that ask for a new window open in the same view, if allowed.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url,
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        switch NavigationPolicy.decide(url, isMainFrame: true) {
        case .allow: webView.load(URLRequest(url: url))
        case .redirect(let target): webView.load(URLRequest(url: target))
        case .block: Self.log.info("blocked new window \(url.absoluteString, privacy: .public)")
        }
        return nil
    }
}

/// Breaks the retain cycle between WKUserContentController and the controller.
final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    var onMessage: (@MainActor (Any) -> Void)?

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        MainActor.assumeIsolated { onMessage?(body) }
    }
}

/// Plain container so SwiftUI can host the long-lived web view.
final class WKWebViewContainer: UIView {
    init(webView: WKWebView) {
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}
