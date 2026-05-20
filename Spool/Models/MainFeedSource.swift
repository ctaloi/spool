import Foundation

/// What the main list view is showing. Replaces the modal-sheet model
/// where Browse and Library lived in their own NavigationStacks — now
/// they all flow through the same hero / search / list scaffolding in
/// `StoryListView`, picked via the title-bar selector or the sidebar.
enum MainFeedSource: Hashable {
    case category(HNStoryFeed)
    case trending
    case bestOf(BestOfWindow)
    case saved
    case spool
    case archive
    case following
    case mentions

    /// Title used in the hero, the inline navbar selector, and the
    /// large nav title for accessibility.
    var displayTitle: String {
        switch self {
        case .category(let feed):
            switch feed {
            case .ask: return "Ask HN"
            case .show: return "Show HN"
            case .job: return "Jobs"
            default:   return "\(feed.title) Stories"
            }
        case .trending:
            return "Trending"
        case .bestOf(let window):
            return "Best of \(window.title)"
        case .saved:
            return "Saved"
        case .spool:
            return "Spool"
        case .archive:
            return "Archive"
        case .following:
            return "Following"
        case .mentions:
            return "Mentions"
        }
    }

    /// SF Symbol shown alongside the title.
    var icon: String {
        switch self {
        case .category(let feed):
            return feed.icon
        case .trending:
            return "chart.line.uptrend.xyaxis"
        case .bestOf(let window):
            return window.icon
        case .saved:
            return "bookmark.fill"
        case .spool:
            return "headphones"
        case .archive:
            return "archivebox"
        case .following:
            return "person.2.fill"
        case .mentions:
            return "at"
        }
    }

    /// Search bar appears only for the live HN category feeds. Library
    /// and curated views suppress it — searching a saved list would be
    /// a different feature (filtering) entirely.
    var supportsSearch: Bool {
        if case .category = self { return true }
        return false
    }

    /// Map a deep-link keyword (`spool://feed/<keyword>`) to a source.
    /// Returns nil for unknown keywords so the router can drop the
    /// request rather than navigate somewhere surprising.
    static func from(keyword: String) -> MainFeedSource? {
        switch keyword.lowercased() {
        case "top":      return .category(.top)
        case "new":      return .category(.new)
        case "best":     return .category(.best)
        case "ask":      return .category(.ask)
        case "show":     return .category(.show)
        case "jobs", "job": return .category(.job)
        case "trending": return .trending
        case "saved":    return .saved
        case "spool":    return .spool
        case "archive":  return .archive
        case "following": return .following
        case "mentions": return .mentions
        default:         return nil
        }
    }
}
