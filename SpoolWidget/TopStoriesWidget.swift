import WidgetKit
import SwiftUI
import AppIntents

/// A point-in-time view of an HN feed for the widget timeline. The
/// `feed` value reflects the user's `TopStoriesConfigurationIntent`
/// choice — the widget views read it to render the right title in
/// their headers.
struct TopStoriesEntry: TimelineEntry {
    let date: Date
    let stories: [HNItem]
    /// Which feed this entry was fetched from. Drives the header
    /// title in each widget size and the empty-state copy.
    let feed: HNStoryFeedEntity
    /// Set when the network fetch failed and we're showing whatever
    /// was last cached. The view uses this to dim slightly so the
    /// user has a hint the data may be stale.
    let isStale: Bool

    static let placeholder = TopStoriesEntry(
        date: .now,
        stories: HNItem.widgetPlaceholders,
        feed: .top,
        isStale: false
    )
}

/// AppIntent-driven timeline provider. iOS calls into this every
/// ~30 minutes (best-effort, can stretch under battery pressure)
/// passing the user's current configuration so we know which feed
/// to fetch.
struct TopStoriesProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TopStoriesEntry {
        .placeholder
    }

    func snapshot(
        for configuration: TopStoriesConfigurationIntent,
        in context: Context
    ) async -> TopStoriesEntry {
        await fetch(for: configuration.feed)
    }

    func timeline(
        for configuration: TopStoriesConfigurationIntent,
        in context: Context
    ) async -> Timeline<TopStoriesEntry> {
        let entry = await fetch(for: configuration.feed)
        // 30-minute cadence — frequent enough that the widget
        // feels live, sparse enough that we don't burn through
        // iOS's per-widget runtime budget.
        let next = Date.now.addingTimeInterval(30 * 60)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func fetch(for feedEntity: HNStoryFeedEntity) async -> TopStoriesEntry {
        do {
            let ids = try await HNAPI.shared.storyIDs(for: feedEntity.feed)
            let stories = try await HNAPI.shared.items(ids: Array(ids.prefix(8)))
            return TopStoriesEntry(
                date: .now,
                stories: stories,
                feed: feedEntity,
                isStale: false
            )
        } catch {
            return TopStoriesEntry(
                date: .now,
                stories: [],
                feed: feedEntity,
                isStale: true
            )
        }
    }
}

struct TopStoriesWidget: Widget {
    let kind = "TopStoriesWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: TopStoriesConfigurationIntent.self,
            provider: TopStoriesProvider()
        ) { entry in
            TopStoriesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Hacker News")
        .description("Top stories from Hacker News — choose your feed.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryRectangular,
        ])
    }
}
