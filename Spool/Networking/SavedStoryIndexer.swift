import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Indexes the user's Saved Stories into CoreSpotlight so they show
/// up in iOS system search. Tapping a result deep-links into the
/// story via the same `spool://` URL scheme the widget uses.
///
/// Membership is mirror-driven — every call to `syncAll(_:)` rebuilds
/// the index from the source of truth (the SavedStory @Query result),
/// so there's no need to track separate add/remove events. The cost
/// is bounded: re-indexing 100 items is ~ms.
enum SavedStoryIndexer {
    private static let domain = "news.getspool.app.savedStories"

    /// Replace the entire indexed set with the supplied snapshot.
    /// Idempotent — calling repeatedly with the same list is a no-op
    /// after the first run (CoreSpotlight deduplicates by uniqueID).
    static func syncAll(_ stories: [SavedStory]) {
        let items = stories.map(makeItem(_:))
        let index = CSSearchableIndex.default()
        // Wipe the previous set so removed saves disappear from
        // Spotlight too — CoreSpotlight doesn't auto-prune.
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            index.indexSearchableItems(items) { _ in }
        }
    }

    /// Surface a single story right after the user saves it, without
    /// waiting for the full sync. Cheap fast path.
    static func index(_ story: SavedStory) {
        CSSearchableIndex.default().indexSearchableItems([makeItem(story)]) { _ in }
    }

    /// Drop a single story's index entry after unsave. Keeps Spotlight
    /// from showing stale results.
    static func deindex(_ id: Int) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: [String(id)]
        ) { _ in }
    }

    private static func makeItem(_ story: SavedStory) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: UTType.text)
        attrs.title = story.title
        attrs.contentDescription = story.urlString ?? "Spool story"
        if let author = story.author, !author.isEmpty {
            attrs.contentCreationDate = story.savedAt
            attrs.contentSources = [author]
        }
        // spool://story/<id> deep-link — handled in SpoolApp via
        // .onOpenURL.
        attrs.contentURL = URL(string: "spool://story/\(story.id)")
        return CSSearchableItem(
            uniqueIdentifier: String(story.id),
            domainIdentifier: domain,
            attributeSet: attrs
        )
    }
}
