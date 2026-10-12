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
    nonisolated static func parse(_ source: String, now: Date = Date()) -> Rules? {
        guard source.utf8.count <= maxBytes else { return nil }
        guard let firstLine = source.split(separator: "\n", maxSplits: 1).first,
              let range = firstLine.range(of: #"tubeclean-rules version=(\d{1,18})"#, options: .regularExpression)
        else { return nil }
        let digits = firstLine[range].split(separator: "=").last.map(String.init) ?? ""
        guard let version = Int64(digits), version <= maxAcceptableVersion(now: now) else { return nil }
        return Rules(version: version, source: source)
    }

    func refreshIfDue(force: Bool = false) async {
        guard let remoteURL, !refreshing else { return }
        let last = defaults.double(forKey: "rulesLastCheck")
        let now = Date().timeIntervalSince1970
        guard force || now - last >= Self.refreshInterval else { return }
        refreshing = true
        defer { refreshing = false }

        var request = URLRequest(url: remoteURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        if let etag = defaults.string(forKey: "rulesETag") {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            defaults.set(now, forKey: "rulesLastCheck")
            if http.statusCode == 304 { return }
            guard http.statusCode == 200,
                  let text = String(data: data, encoding: .utf8),
                  let rules = Self.parse(text) else {
                Self.log.error("rules download rejected (HTTP \(http.statusCode))")
                return
            }
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                defaults.set(etag, forKey: "rulesETag")
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
