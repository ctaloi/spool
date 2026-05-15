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

    init(
        id: Int,
        title: String,
        urlString: String?,
        author: String?,
        score: Int?,
        descendants: Int?,
        savedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.author = author
        self.score = score
        self.descendants = descendants
        self.savedAt = savedAt
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
            dead: nil
        )
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
