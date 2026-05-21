import Foundation

/// One-line editorial subtitles for each feed source. Rendered as a
/// quiet, secondary-text caption at the top of the list to give each
/// view a touch of identity without changing the layout.
///
/// Copy lives here, not scattered through views, so it can be tuned
/// in one place and translated as one unit.
enum FeedDescriptions {
    /// Subtitle for the active feed, or `nil` if the feed should
    /// render without one (avoids forcing copy where the screen is
    /// already self-evident — e.g., the empty-by-design Spool).
    static func subtitle(for source: MainFeedSource) -> String? {
        switch source {
        case .category(let feed):
            switch feed {
            case .top:  return "What HN is reading now."
            case .new:  return "Fresh submissions as they arrive."
            case .best: return "High-signal stories from across HN."
            case .ask:  return "Questions and discussions from the community."
            case .show: return "Things people built."
            case .job:  return "Hiring posts from the HN community."
            }
        case .trending:
            return "Stories gaining attention right now."
        case .bestOf(let window):
            switch window {
            case .today: return "The day's strongest threads."
            case .week:  return "The stories HN kept coming back to."
            case .month: return "A slower look at what mattered."
            case .year:  return "The year's most durable conversations."
            }
        case .saved:
            return "Stories you've bookmarked."
        case .spool:
            return "Your audio queue."
        case .archive:
            return "Stories you've finished listening to."
        case .following:
            return "Recent posts from people you follow."
        case .mentions:
            return "Replies to your comments."
        }
    }
}
