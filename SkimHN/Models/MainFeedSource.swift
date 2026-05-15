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
    case readLater
    case following

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
        case .readLater:
            return "Read Later"
        case .following:
            return "Following"
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
        case .readLater:
            return "tray.fill"
        case .following:
            return "person.2.fill"
        }
    }

    /// Search bar appears only for the live HN category feeds. Library
    /// and curated views suppress it — searching a saved list would be
    /// a different feature (filtering) entirely.
    var supportsSearch: Bool {
        if case .category = self { return true }
        return false
    }
}
