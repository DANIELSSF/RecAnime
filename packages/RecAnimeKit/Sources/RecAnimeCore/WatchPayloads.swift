import Foundation

/// Supabase session minted by the iPhone for the Watch (WatchConnectivity application context).
public struct WatchSession: Codable, Sendable, Hashable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var userId: String
    public var email: String
    public var mintedAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date, userId: String, email: String, mintedAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userId = userId
        self.email = email
        self.mintedAt = mintedAt
    }
}

/// Last-known data pushed from the iPhone so the Watch has content before its first fetch.
public struct WatchSnapshot: Codable, Sendable, Hashable {
    public var watching: [LibraryItem]
    public var schedule: [ScheduleItem]
    public var generatedAt: Date

    public init(watching: [LibraryItem], schedule: [ScheduleItem], generatedAt: Date) {
        self.watching = watching
        self.schedule = schedule
        self.generatedAt = generatedAt
    }
}

/// Compact data the complication renders (written to the App Group by the Watch app).
public struct ComplicationSnapshot: Codable, Sendable, Hashable {
    public struct Item: Codable, Sendable, Hashable, Identifiable {
        public var malID: Int
        public var title: String
        public var nextEpisode: Int?
        public var nextAiringAt: Date?
        public var episodesWatched: Int
        public var episodesTotal: Int?

        public var id: Int {
            malID
        }

        public init(malID: Int, title: String, nextEpisode: Int?, nextAiringAt: Date?, episodesWatched: Int, episodesTotal: Int?) {
            self.malID = malID
            self.title = title
            self.nextEpisode = nextEpisode
            self.nextAiringAt = nextAiringAt
            self.episodesWatched = episodesWatched
            self.episodesTotal = episodesTotal
        }
    }

    public var generatedAt: Date
    public var items: [Item]

    public init(generatedAt: Date, items: [Item]) {
        self.generatedAt = generatedAt
        self.items = items
    }

    /// Builds the complication data from the schedule, soonest airing first.
    public static func from(schedule: [ScheduleItem], now: Date) -> ComplicationSnapshot {
        let items = schedule
            .sorted { ($0.nextAiringAt ?? .distantFuture) < ($1.nextAiringAt ?? .distantFuture) }
            .map { Item(
                malID: $0.malId,
                title: $0.title,
                nextEpisode: $0.nextEpisodeNumber,
                nextAiringAt: $0.nextAiringAt,
                episodesWatched: $0.episodesWatched,
                episodesTotal: $0.episodesTotal
            ) }
        return ComplicationSnapshot(generatedAt: now, items: items)
    }
}

/// Message envelope exchanged over WatchConnectivity (JSON in the "payload" key).
public enum WatchMessageType: String, Codable, Sendable {
    case context
    case signedOut
    case needsSession
    case libraryChanged
    case complication
}
