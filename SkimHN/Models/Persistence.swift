import Foundation
import SwiftData

/// Persisted record of a story the user explicitly saved for later. We
/// snapshot enough fields to render the Saved tab without re-fetching, and
/// reload the live HNItem only when the user taps in.
@Model
final class SavedStory {
    @Attribute(.unique) var id: Int
    var title: String
    var urlString: String?
    var author: String?
    var score: Int?
    var descendants: Int?
    var savedAt: Date
    /// Pre-generated AI summary populated by a background task fired
    /// when the user saves. nil until the background task completes.
    var cachedSummaryText: String?
    var cachedSummaryGeneratedAt: Date?

    init(
        id: Int,
        title: String,
        urlString: String?,
        author: String?,
        score: Int?,
        descendants: Int?,
        savedAt: Date = .now,
        cachedSummaryText: String? = nil,
        cachedSummaryGeneratedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.author = author
        self.score = score
        self.descendants = descendants
        self.savedAt = savedAt
        self.cachedSummaryText = cachedSummaryText
        self.cachedSummaryGeneratedAt = cachedSummaryGeneratedAt
    }

    /// Build a transient HNItem so the Saved tab can navigate into
    /// `StoryDetailView` (which re-fetches from HNAPI anyway).
    var asHNItem: HNItem {
        HNItem(
            id: id,
            type: "story",
            by: author,
            time: nil,
            text: nil,
            url: urlString,
            title: title,
            score: score,
            descendants: descendants,
            kids: nil,
            parent: nil,
            deleted: nil,
            dead: nil,
            parts: nil
        )
    }
}

/// Persisted record of a story the user queued for later reading. Same
/// shape as `SavedStory` — different intent. Saved is a permanent
/// archive ("bookmark this"); Read Later is a working queue ("get to
/// this today, then clear it").
@Model
final class ReadLaterStory {
    @Attribute(.unique) var id: Int
    var title: String
    var urlString: String?
    var author: String?
    var score: Int?
    var descendants: Int?
    var queuedAt: Date

    init(
        id: Int,
        title: String,
        urlString: String?,
        author: String?,
        score: Int?,
        descendants: Int?,
        queuedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.author = author
        self.score = score
        self.descendants = descendants
        self.queuedAt = queuedAt
    }

    var asHNItem: HNItem {
        HNItem(
            id: id,
            type: "story",
            by: author,
            time: nil,
            text: nil,
            url: urlString,
            title: title,
            score: score,
            descendants: descendants,
            kids: nil,
            parent: nil,
            deleted: nil,
            dead: nil,
            parts: nil
        )
    }
}

/// A Hacker News user the local user is following. Their recent
/// submissions get pulled into the inline `Following` feed on demand.
@Model
final class FollowedUser {
    @Attribute(.unique) var username: String
    var addedAt: Date

    init(username: String, addedAt: Date = .now) {
        self.username = username
        self.addedAt = addedAt
    }
}

/// Per-feed-load snapshot of a story's score, used by the Trending
/// feed. Each successful `reload()` of any feed inserts one snapshot per
/// visible story. Trending sorts by velocity = (latest - earliest) /
/// hours between, computed over snapshots from the last 24h. Older rows
/// are pruned opportunistically when the trending feed is queried so
/// the table doesn't grow without bound.
@Model
final class ScoreSnapshot {
    var itemID: Int
    var score: Int
    var capturedAt: Date

    init(itemID: Int, score: Int, capturedAt: Date = .now) {
        self.itemID = itemID
        self.score = score
        self.capturedAt = capturedAt
    }
}

/// Marker that the user has opened a story before. Used to dim rows in the
/// feed.
@Model
final class ReadStory {
    @Attribute(.unique) var id: Int
    var readAt: Date

    init(id: Int, readAt: Date = .now) {
        self.id = id
        self.readAt = readAt
    }
}
