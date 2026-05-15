import WidgetKit
import SwiftUI

/// A point-in-time view of the HN top feed for the widget timeline.
struct TopStoriesEntry: TimelineEntry {
    let date: Date
    let stories: [HNItem]
    /// Set when the network fetch failed and we're showing whatever
    /// was last cached. The view uses this to dim slightly so the
    /// user has a hint the data may be stale.
    let isStale: Bool

    static let placeholder = TopStoriesEntry(
        date: .now,
        stories: HNItem.widgetPlaceholders,
        isStale: false
    )
}

/// Timeline provider — refreshes every 30 minutes (best-effort; iOS
/// can stretch this on a busy system). One entry per timeline; the
/// system will request another when our `.after(...)` policy fires.
struct TopStoriesProvider: TimelineProvider {
    func placeholder(in context: Context) -> TopStoriesEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (TopStoriesEntry) -> Void) {
        Task {
            let entry = await fetch()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TopStoriesEntry>) -> Void) {
        Task {
            let entry = await fetch()
            // 30-minute cadence — frequent enough that the widget
            // feels live, sparse enough that we don't burn through
            // iOS's per-widget runtime budget.
            let next = Date.now.addingTimeInterval(30 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func fetch() async -> TopStoriesEntry {
        do {
            let ids = try await HNAPI.shared.storyIDs(for: .top)
            let stories = try await HNAPI.shared.items(ids: Array(ids.prefix(8)))
            return TopStoriesEntry(date: .now, stories: stories, isStale: false)
        } catch {
            return TopStoriesEntry(date: .now, stories: [], isStale: true)
        }
    }
}

struct TopStoriesWidget: Widget {
    let kind = "TopStoriesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TopStoriesProvider()) { entry in
            TopStoriesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Top Stories")
        .description("The current top stories on Hacker News, refreshed every 30 minutes.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryRectangular,
        ])
    }
}
