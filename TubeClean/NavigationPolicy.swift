import Foundation

/// Decides where the web view may go. Pure, so it can be unit tested.
enum NavigationPolicy {
    enum Decision: Equatable {
        /// Load it.
        case allow
        /// Load this URL instead (a Shorts page goes to the home page).
        case redirect(URL)
        /// Do nothing.
        case block
    }

    static let home = URL(string: "https://www.youtube.com/")!

    private static func isYouTube(_ h: String) -> Bool {
        h == "youtube.com" || h.hasSuffix(".youtube.com")
    }

    /// Google's sign-in hosts, listed exactly. Pattern matching on country
    /// domains let in hosts Google does not own (accounts.google.co.de).
    /// Nothing else on Google is allowed (no myaccount, search, sites, AMP).
    private static let googleSignInHosts: Set<String> = [
        "accounts.google.com", "accounts.google.co.uk",
    ]

    private static func isGoogleSignIn(_ h: String) -> Bool {
        googleSignInHosts.contains(h)
    }

    /// Hosts the main frame may show.
    static func isAllowedHost(_ host: String) -> Bool {
        let h = host.lowercased()
        return isYouTube(h) || h == "youtu.be" || isGoogleSignIn(h)
    }

    /// Hosts an embedded frame may show: the main-frame hosts, plus the
    /// sign-in helpers (reCAPTCHA, static files).
    static func isAllowedFrameHost(_ host: String, path: String) -> Bool {
        let h = host.lowercased()
        if isAllowedHost(h) { return true }
        if h == "gstatic.com" || h.hasSuffix(".gstatic.com") { return true }
        if (h == "www.google.com" || h == "www.recaptcha.net") && path.hasPrefix("/recaptcha/") { return true }
        return false
    }

    /// True for YouTube Shorts pages: /shorts/<id>, /feed/shorts, and a
    /// channel's Shorts tab.
    static func isShorts(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), isYouTube(host) else { return false }
        let p = url.path
        if p == "/shorts" || p.hasPrefix("/shorts/") || p == "/feed/shorts" { return true }
        let parts = p.split(separator: "/")
        if parts.count == 2, parts[1] == "shorts" { return parts[0].hasPrefix("@") }
        if parts.count == 3, parts[2] == "shorts" { return ["channel", "c", "user"].contains(String(parts[0])) }
        return false
    }

    static func decide(_ url: URL, isMainFrame: Bool) -> Decision {
        guard let scheme = url.scheme?.lowercased() else { return .block }
        // Inline documents (srcdoc frames, blob players) may load in frames.
        // In the main frame they could hold a page the script never runs on.
        if scheme == "about" || scheme == "blob" || scheme == "data" {
            return isMainFrame ? .block : .allow
        }
        guard scheme == "https" || scheme == "http", let host = url.host?.lowercased() else { return .block }

        if !isMainFrame {
            return isAllowedFrameHost(host, path: url.path) ? .allow : .block
        }
        guard isAllowedHost(host) else { return .block }
        // youtube.com/redirect is the "you are leaving YouTube" page for
        // outside links; it leads nowhere we allow.
        if isYouTube(host) && url.path == "/redirect" { return .block }
        if isShorts(url) { return .redirect(home) }
        // YouTube's own script moves touch devices to the mobile site. Keep
        // the desktop site: it is what Safari on iPad shows, and what the
        // blocking rules target and were tested on. app=desktop stops the
        // bounce back.
        if host == "m.youtube.com" {
            var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
            c?.host = "www.youtube.com"
            c?.scheme = "https"
            var items = (c?.queryItems ?? []).filter { $0.name != "app" }
            items.append(URLQueryItem(name: "app", value: "desktop"))
            c?.queryItems = items
            if let target = c?.url { return .redirect(target) }
        }
        // youtu.be/<id> is a short link to a normal video.
        if host == "youtu.be" {
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !id.isEmpty, let watch = URL(string: "https://www.youtube.com/watch?v=\(id)") {
                return .redirect(watch)
            }
            return .redirect(home)
        }
        return .allow
    }
}
