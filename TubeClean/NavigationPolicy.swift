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

    /// Hosts the main frame may show: YouTube itself, plus Google's sign-in
    /// and consent pages. Sign-in hops through country domains such as
    /// accounts.google.co.uk, so any google.<tld> counts.
    static func isAllowedHost(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "youtube.com" || h.hasSuffix(".youtube.com") { return true }
        if h == "youtu.be" { return true }
        // google.com, accounts.google.com, accounts.google.co.uk, ...
        let labels = h.split(separator: ".")
        if let i = labels.lastIndex(of: "google") {
            let tld = labels[(i + 1)...]
            let tldOK = tld.count == 1 || (tld.count == 2 && tld.first.map { ["co", "com"].contains($0) } == true)
            return !tld.isEmpty && tldOK
        }
        return false
    }

    /// True for YouTube Shorts pages: /shorts/<id>, /feed/shorts, and a
    /// channel's Shorts tab.
    static func isShorts(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              host == "youtube.com" || host.hasSuffix(".youtube.com") else { return false }
        let p = url.path
        if p == "/shorts" || p.hasPrefix("/shorts/") || p == "/feed/shorts" { return true }
        let parts = p.split(separator: "/")
        if parts.count == 2, parts[1] == "shorts" { return parts[0].hasPrefix("@") }
        if parts.count == 3, parts[2] == "shorts" { return ["channel", "c", "user"].contains(String(parts[0])) }
        return false
    }

    static func decide(_ url: URL, isMainFrame: Bool) -> Decision {
        guard let scheme = url.scheme?.lowercased() else { return .block }
        // Sub-frames (players, sign-in widgets) and inline content may load.
        if !isMainFrame { return .allow }
        if scheme == "about" || scheme == "blob" || scheme == "data" { return .allow }
        guard scheme == "https" || scheme == "http", let host = url.host else { return .block }
        guard isAllowedHost(host) else { return .block }
        if isShorts(url) { return .redirect(home) }
        // youtu.be/<id> is a short link to a normal video.
        if host.lowercased() == "youtu.be" {
            let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !id.isEmpty, let watch = URL(string: "https://www.youtube.com/watch?v=\(id)") {
                return .redirect(watch)
            }
            return .redirect(home)
        }
        return .allow
    }
}
