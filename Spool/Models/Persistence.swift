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
/// archive ("bookmark this"); Spool is a working queue ("get to
/// this today, then clear it") with playable audio summaries.
@Model
final class SpooledStory {
    @Attribute(.unique) var id: Int
    var title: String
    var urlString: String?
    var author: String?
    var score: Int?
    var descendants: Int?
    var queuedAt: Date
    /// User-facing queue position. Drives the @Query sort and the
    /// drag-to-reorder UI. Default value (`Int.max - id`) puts
    /// freshly-migrated rows in roughly newest-first order until
    /// the user reorders them.
    var position: Int = 0
    /// Pre-generated article summary (Markdown). Populated by
    /// SummaryPrefetcher when the item is added; nil until the
    /// background task completes.
    var cachedArticleSummary: String?
    /// Pre-generated comments summary (Markdown). Optional even
    /// after generation runs — a story with no comments at queue-
    /// time leaves this nil.
    var cachedThreadSummary: String?
    /// When the prefetch completed. Used to decide whether to
    /// refresh on long-tenured items.
    var cachedSummaryGeneratedAt: Date?
    /// When the audio pre-render landed in the cache. Used by the
    /// Spool UI to show "Ready to play" vs "Preparing audio…" per
    /// item. nil means either the summary itself isn't ready yet
    /// (rendering hasn't started) OR the render is in flight (we
    /// only stamp this once a .caf finalizes into the cache).
    var cachedAudioGeneratedAt: Date?
    /// When the user (or the Play All sweep) archived this item.
    /// nil = still in the active spool; non-nil = in the Archive.
    /// Both the live spool and the archive are stored in the same
    /// table; queries filter on this field so the user can restore
    /// "deleted" items without losing them outright.
    var archivedAt: Date?

    init(
        id: Int,
        title: String,
        urlString: String?,
        author: String?,
        score: Int?,
        descendants: Int?,
        queuedAt: Date = .now,
        position: Int = 0,
        cachedArticleSummary: String? = nil,
        cachedThreadSummary: String? = nil,
        cachedSummaryGeneratedAt: Date? = nil,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.author = author
        self.score = score
        self.descendants = descendants
        self.queuedAt = queuedAt
        self.position = position
        self.cachedArticleSummary = cachedArticleSummary
        self.cachedThreadSummary = cachedThreadSummary
        self.cachedSummaryGeneratedAt = cachedSummaryGeneratedAt
        self.archivedAt = archivedAt
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

    /// Combined audio script for this item's playlist entry. Uses
    /// the "Article summary. ... Discussion. ..." prefixing so
    /// listeners get a spoken cue at each section transition.
    /// Returns nil when neither summary is available.
    var playlistScript: String? {
        var parts: [String] = []
        if let s = cachedArticleSummary, !s.isEmpty {
            parts.append("Article summary. \(s)")
        }
        if let s = cachedThreadSummary, !s.isEmpty {
            parts.append("Discussion. \(s)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Rough seconds-to-listen estimate based on the cached
    /// summaries' character count. Typical TTS speed ≈ 150 wpm =
    /// 2.5 wps; average English word = ~5 chars + space. So a
    /// reasonable estimate is `chars / 15` seconds.
    var estimatedDurationSeconds: Int {
        let script = playlistScript ?? ""
        guard !script.isEmpty else { return 0 }
        return max(15, script.count / 15)
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

/// A reply (comment) the user has already seen in the Mentions feed.
/// Anything not in this table is "unread", which drives the badge
/// count. A SwiftData set rather than a single high-water-mark Int —
/// the latter would let a later-arriving low-ID reply get silently
/// marked seen when the user views a higher-ID reply in the same
/// fetch.
@Model
final class SeenMention {
    @Attribute(.unique) var id: Int
    var seenAt: Date

    init(id: Int, seenAt: Date = .now) {
        self.id = id
        self.seenAt = seenAt
    }
}
