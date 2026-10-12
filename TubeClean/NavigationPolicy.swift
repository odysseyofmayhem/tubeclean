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

    /// accounts.google.com, accounts.google.co.uk, accounts.google.de, ...
    /// Exactly `accounts.google.<tld>` or `accounts.google.co.<cc>`; nothing
    /// else on Google (no myaccount, search, sites, AMP viewer).
    private static func isGoogleSignIn(_ h: String) -> Bool {
        let labels = h.split(separator: ".").map(String.init)
        guard labels.count >= 3, labels[0] == "accounts", labels[1] == "google" else { return false }
        let tld = labels.dropFirst(2)
        let isCC = { (s: String) in s.count == 2 && s.allSatisfy(\.isLetter) }
        if tld.count == 1 { return tld.first == "com" || isCC(tld.first!) }
        if tld.count == 2 { return ["co", "com"].contains(tld.first!) && isCC(tld.last!) }
        return false
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
        // Inline documents (srcdoc frames, blob players) stay in the page.
        if scheme == "about" || scheme == "blob" || scheme == "data" {
            return isMainFrame && scheme != "about" ? .block : .allow
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
