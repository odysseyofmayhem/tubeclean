import Foundation
import os

/// Holds the blocking script and keeps it current.
///
/// Three copies, newest wins:
///   1. bundled in the app (always there, may be old)
///   2. cached on disk from the last good download
///   3. downloaded from `TCRulesURL` (Info.plist), at most every few hours
///
/// The script's first line carries its version:
///   /* tubeclean-rules version=202610120300 */
@MainActor
final class RulesStore {
    struct Rules: Equatable {
        let version: Int64
        let source: String
    }

    private static let log = Logger(subsystem: "uk.co.ilmaris.tubeclean", category: "rules")
    private static let refreshInterval: TimeInterval = 6 * 60 * 60
    nonisolated private static let maxBytes = 2 * 1024 * 1024

    private(set) var current: Rules
    /// Called on the main actor when a newer script has been installed.
    var onUpdate: ((Rules) -> Void)?

    private let remoteURL: URL?
    private let cacheURL: URL
    private let defaults: UserDefaults
    private var refreshing = false

    init(bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cacheURL = dir.appendingPathComponent("tubeclean.js")
        remoteURL = (bundle.object(forInfoDictionaryKey: "TCRulesURL") as? String).flatMap(URL.init(string:))

        let bundled = bundle.url(forResource: "tubeclean", withExtension: "js")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            .flatMap { Self.parse($0) }
        let cached = (try? String(contentsOf: cacheURL, encoding: .utf8)).flatMap { Self.parse($0) }

        switch (bundled, cached) {
        case let (b?, c?): current = c.version > b.version ? c : b
        case let (b?, nil): current = b
        case let (nil, c?): current = c
        case (nil, nil):
            // Should not happen: the bundle always ships a script.
            current = Rules(version: 0, source: "")
        }
        Self.log.info("rules version \(self.current.version) in use")
    }

    /// Versions are UTC timestamps (yyyyMMddHHmm). One more than a day ahead
    /// is a mistake or an attack: accepting it would block every later update.
    nonisolated static func maxAcceptableVersion(now: Date = Date()) -> Int64 {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now.addingTimeInterval(86_400))
        return Int64(c.year!) * 100_000_000 + Int64(c.month!) * 1_000_000
            + Int64(c.day!) * 10_000 + Int64(c.hour!) * 100 + Int64(c.minute!)
    }

    /// Parses and sanity-checks a script. Returns nil if it isn't one of ours.
    /// The first line must be exactly the header, with a real UTC timestamp.
    nonisolated static func parse(_ source: String, now: Date = Date()) -> Rules? {
        guard source.utf8.count <= maxBytes,
              let firstLine = source.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first,
              firstLine.wholeMatch(of: /\/\* tubeclean-rules version=\d{12} \*\//) != nil
        else { return nil }
        let digits = firstLine.dropFirst("/* tubeclean-rules version=".count).prefix(12)
        guard let version = Int64(digits), isTimestamp(String(digits)),
              version <= maxAcceptableVersion(now: now) else { return nil }
        return Rules(version: version, source: source)
    }

    /// True if yyyyMMddHHmm is a real date and time.
    nonisolated private static func isTimestamp(_ s: String) -> Bool {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMddHHmm"
        f.isLenient = false
        guard let d = f.date(from: s) else { return false }
        return f.string(from: d) == s
    }

    func refreshIfDue(force: Bool = false) async {
        guard let remoteURL, !refreshing else { return }
        let last = defaults.double(forKey: "rulesLastCheck")
        let now = Date().timeIntervalSince1970
        guard force || now - last >= Self.refreshInterval else { return }
        refreshing = true
        defer { refreshing = false }

        // No ETag: the file is ~100 KB every 6 h, and a stale ETag could
        // keep answering 304 while the app holds older rules.
        let request = URLRequest(url: remoteURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            defaults.set(now, forKey: "rulesLastCheck")
            guard http.statusCode == 200,
                  let text = String(data: data, encoding: .utf8),
                  let rules = Self.parse(text) else {
                Self.log.error("rules download rejected (HTTP \(http.statusCode))")
                return
            }
            guard rules.version > current.version else { return }
            try data.write(to: cacheURL, options: .atomic)
            current = rules
            Self.log.info("rules updated to version \(rules.version)")
            onUpdate?(rules)
        } catch {
            // Offline or GitHub down: keep what we have, try again next time.
            Self.log.error("rules refresh failed: \(error.localizedDescription)")
        }
    }
}
