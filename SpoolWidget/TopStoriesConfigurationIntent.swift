import AppIntents
import WidgetKit

/// Widget configuration the user edits via long-press → Edit.
/// Lets them pick which HN feed the widget pulls from.
struct TopStoriesConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Spool Widget"
    static var description = IntentDescription(
        "Pick which HN feed this widget should display."
    )

    @Parameter(title: "Feed", default: .top)
    var feed: HNStoryFeedEntity
}

/// AppEnum mirror of `HNStoryFeed`. The widget target imports the
/// model file so the underlying enum is available, but
/// `WidgetConfigurationIntent` parameters need an `AppEnum`-conforming
/// type that we can't add directly to the data model without bringing
/// the AppIntents framework into the rest of the app.
enum HNStoryFeedEntity: String, AppEnum {
    case top
    case new
    case best
    case ask
    case show
    case job

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "HN Feed")

    static var caseDisplayRepresentations: [HNStoryFeedEntity: DisplayRepresentation] = [
        .top:  DisplayRepresentation(title: "Top Stories",  image: .init(systemName: "flame.fill")),
        .new:  DisplayRepresentation(title: "New Stories",  image: .init(systemName: "clock.fill")),
        .best: DisplayRepresentation(title: "Best Stories", image: .init(systemName: "star.fill")),
        .ask:  DisplayRepresentation(title: "Ask HN",       image: .init(systemName: "questionmark.bubble.fill")),
        .show: DisplayRepresentation(title: "Show HN",      image: .init(systemName: "eye.fill")),
        .job:  DisplayRepresentation(title: "Jobs",         image: .init(systemName: "briefcase.fill")),
    ]

    /// Bridge to the in-app model so the widget's timeline provider
    /// can call `HNAPI.shared.storyIDs(for:)` with the matching feed.
    var feed: HNStoryFeed {
        switch self {
        case .top:  return .top
        case .new:  return .new
        case .best: return .best
        case .ask:  return .ask
        case .show: return .show
        case .job:  return .job
        }
    }

    /// Human-readable label for header chrome inside the widget views.
    var displayName: String {
        switch self {
        case .top:  return "Top Stories"
        case .new:  return "New Stories"
        case .best: return "Best Stories"
        case .ask:  return "Ask HN"
        case .show: return "Show HN"
        case .job:  return "Jobs"
        }
    }
}
