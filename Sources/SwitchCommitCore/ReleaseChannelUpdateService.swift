import Foundation

public struct ReleaseChannelSnapshot: Equatable, Sendable {
    public var latestVersion: String
    public var enclosureURL: URL
    public var checkedAt: Date

    public init(latestVersion: String, enclosureURL: URL, checkedAt: Date = Date()) {
        self.latestVersion = latestVersion
        self.enclosureURL = enclosureURL
        self.checkedAt = checkedAt
    }
}

public struct ReleaseChannelUpdateService {
    public static let defaultFeedURL = URL(string: "https://kwiats.github.io/switch-commit/appcast.xml")!
    public static let defaultTTL: TimeInterval = 12 * 60 * 60

    private let feedURL: URL
    private let cacheURL: URL
    private let ttl: TimeInterval
    private let fetcher: any ReleaseChannelFetching
    private let fileManager: FileManager
    private let now: () -> Date

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        feedURL: URL = ReleaseChannelUpdateService.defaultFeedURL,
        ttl: TimeInterval = ReleaseChannelUpdateService.defaultTTL,
        fetcher: any ReleaseChannelFetching = URLSessionReleaseChannelFetcher(),
        fileManager: FileManager = .default,
        now: @escaping () -> Date = { Date() }
    ) {
        self.feedURL = feedURL
        self.cacheURL = homeDirectory
            .appendingPathComponent(".config/git-account-switcher/update-check-cache.json")
        self.ttl = ttl
        self.fetcher = fetcher
        self.fileManager = fileManager
        self.now = now
    }

    public func cachedSnapshot() -> ReleaseChannelSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? decoder.decode(CacheFile.self, from: data),
              let enclosure = URL(string: decoded.enclosureURL) else {
            return nil
        }
        return ReleaseChannelSnapshot(
            latestVersion: decoded.latestVersion,
            enclosureURL: enclosure,
            checkedAt: decoded.checkedAt
        )
    }

    public func snapshotForOpportunisticCheck(forceRefresh: Bool = false) -> ReleaseChannelSnapshot? {
        if !forceRefresh, let cached = cachedSnapshot() {
            if now().timeIntervalSince(cached.checkedAt) < ttl {
                return cached
            }
        }
        return try? refresh()
    }

    public func refresh() throws -> ReleaseChannelSnapshot {
        let xml = try fetcher.fetchAppcastXML(from: feedURL)
        let parsed = try Self.parseAppcast(xml)
        let snapshot = ReleaseChannelSnapshot(
            latestVersion: parsed.version,
            enclosureURL: parsed.enclosureURL,
            checkedAt: now()
        )
        try persist(snapshot)
        return snapshot
    }

    public func availableUpdate(currentVersion: String, forceRefresh: Bool) -> ReleaseChannelSnapshot? {
        guard let snapshot = forceRefresh
            ? (try? refresh())
            : snapshotForOpportunisticCheck(forceRefresh: false) else {
            return nil
        }
        guard VersionComparator.isNewer(snapshot.latestVersion, than: currentVersion) else {
            return nil
        }
        return snapshot
    }

    public static func parseAppcast(_ xml: String) throws -> (version: String, enclosureURL: URL) {
        // Prefer first item (appcast is newest-first in our channel).
        let itemPattern = #"<item>([\s\S]*?)</item>"#
        guard let itemRegex = try? NSRegularExpression(pattern: itemPattern),
              let itemMatch = itemRegex.firstMatch(
                in: xml,
                range: NSRange(xml.startIndex..., in: xml)
              ),
              let itemRange = Range(itemMatch.range(at: 1), in: xml) else {
            throw ReleaseChannelError.invalidAppcast
        }
        let item = String(xml[itemRange])

        let version =
            firstCapture(in: item, pattern: #"<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>"#)
            ?? firstCapture(in: item, pattern: #"<sparkle:version>([^<]+)</sparkle:version>"#)
            ?? firstCapture(in: item, pattern: #"<title>([^<]+)</title>"#)
        guard let version else {
            throw ReleaseChannelError.invalidAppcast
        }

        guard let enclosure = firstCapture(
            in: item,
            pattern: #"<enclosure[^>]*url=\"([^\"]+)\""#
        ), let url = URL(string: enclosure) else {
            throw ReleaseChannelError.invalidAppcast
        }
        return (version.trimmingCharacters(in: .whitespacesAndNewlines), url)
    }

    private func persist(_ snapshot: ReleaseChannelSnapshot) throws {
        try fileManager.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let payload = CacheFile(
            latestVersion: snapshot.latestVersion,
            enclosureURL: snapshot.enclosureURL.absoluteString,
            checkedAt: snapshot.checkedAt
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: cacheURL, options: [.atomic])
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private struct CacheFile: Codable {
        var latestVersion: String
        var enclosureURL: String
        var checkedAt: Date
    }
}

public enum ReleaseChannelError: LocalizedError {
    case invalidAppcast

    public var errorDescription: String? {
        switch self {
        case .invalidAppcast:
            return "The Switch Commit release appcast could not be parsed."
        }
    }
}
