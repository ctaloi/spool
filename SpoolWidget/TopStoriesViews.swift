import WidgetKit
import SwiftUI

/// Root dispatcher — picks the right size view from the widget
/// family. Each size renders the same `TopStoriesEntry` data
/// differently, with deep-links into the app via spool://story/<id>.
struct TopStoriesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TopStoriesEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallStoryView(entry: entry)
        case .systemMedium:
            MediumStoryView(entry: entry)
        case .systemLarge:
            LargeStoryView(entry: entry)
        case .accessoryRectangular:
            AccessoryRectangularView(story: entry.stories.first)
        default:
            SmallStoryView(entry: entry)
        }
    }
}

// MARK: - Brand mark

/// Small orange capsule wordmark — "HN" set in thin SF Rounded
/// inside an accent-tinted pill. Anchors the widget to the brand
/// without dominating the layout.
private struct BrandMark: View {
    var body: some View {
        Text("HN")
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange, in: Capsule(style: .continuous))
    }
}

// MARK: - Small

/// One story, hero treatment. Big thin title, accent rank, quiet
/// metadata at the bottom. Tap deep-links to that story.
private struct SmallStoryView: View {
    let entry: TopStoriesEntry

    var body: some View {
        if let story = entry.stories.first {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    BrandMark()
                    Spacer(minLength: 0)
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.orange)
                }

                Spacer(minLength: 6)

                Text(story.title ?? "(no title)")
                    .font(.system(.subheadline, design: .default, weight: .medium))
                    .lineLimit(4)
                    .minimumScaleFactor(0.82)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 6)

                meta(for: story)
            }
            .widgetURL(URL(string: "spool://story/\(story.id)"))
        } else {
            WidgetEmptyState(isStale: entry.isStale)
        }
    }

    @ViewBuilder
    private func meta(for story: HNItem) -> some View {
        HStack(spacing: 8) {
            Label("\(story.score ?? 0)", systemImage: "arrow.up")
            if let descendants = story.descendants {
                Text("·").foregroundStyle(.tertiary)
                Label("\(descendants)", systemImage: "bubble.left")
            }
            Spacer(minLength: 0)
            if let host = story.host {
                Text(host)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption2.monospacedDigit())
        .labelStyle(.titleAndIcon)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Medium

/// Two stories with hero rank glyphs. Cut from 3 → 2 so the
/// titles have room to breathe at the default text size.
private struct MediumStoryView: View {
    let entry: TopStoriesEntry

    var body: some View {
        if entry.stories.isEmpty {
            WidgetEmptyState(isStale: entry.isStale)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                header
                ForEach(Array(entry.stories.prefix(2).enumerated()), id: \.element.id) { idx, story in
                    Link(destination: URL(string: "spool://story/\(story.id)")!) {
                        row(rank: idx + 1, story: story)
                    }
                    if idx == 0 {
                        Divider().opacity(0.4).padding(.vertical, 4)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        HStack {
            BrandMark()
            Text(entry.feed.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(entry.date, format: .dateTime.hour().minute())
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func row(rank: Int, story: HNItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 28, weight: .ultraLight, design: .default))
                .foregroundStyle(Color.orange)
                .frame(width: 26, alignment: .leading)
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 3) {
                Text(story.title ?? "(no title)")
                    .font(.system(.subheadline, design: .default, weight: .medium))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                metaRow(story)
            }
        }
    }

    @ViewBuilder
    private func metaRow(_ story: HNItem) -> some View {
        HStack(spacing: 8) {
            Label("\(story.score ?? 0)", systemImage: "arrow.up")
            Label("\(story.descendants ?? 0)", systemImage: "bubble.left")
            Spacer(minLength: 0)
            if let host = story.host {
                Text(host)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption2.monospacedDigit())
        .labelStyle(.titleAndIcon)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Large

/// Five stories with hero rank typography. Cut from 6 → 5 so each
/// title gets a full two-line slot without crowding the chrome.
private struct LargeStoryView: View {
    let entry: TopStoriesEntry

    var body: some View {
        if entry.stories.isEmpty {
            WidgetEmptyState(isStale: entry.isStale)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                header
                ForEach(Array(entry.stories.prefix(5).enumerated()), id: \.element.id) { idx, story in
                    Link(destination: URL(string: "spool://story/\(story.id)")!) {
                        row(rank: idx + 1, story: story)
                    }
                    if idx < 4 {
                        Divider().opacity(0.3)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            BrandMark()
            Text(entry.feed.displayName)
                .font(.system(.subheadline, design: .default, weight: .light))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Text(entry.date, format: .dateTime.hour().minute())
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func row(rank: Int, story: HNItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 22, weight: .ultraLight, design: .default))
                .foregroundStyle(Color.orange)
                .frame(width: 22, alignment: .trailing)
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 2) {
                Text(story.title ?? "(no title)")
                    .font(.system(.footnote, design: .default, weight: .medium))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                if let host = story.host {
                    Text(host)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(story.score ?? 0)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 24, alignment: .trailing)
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Accessory rectangular (lock screen)

private struct AccessoryRectangularView: View {
    let story: HNItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                Text("#1 on HN")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            Text(story?.title ?? "Loading…")
                .font(.caption.weight(.semibold))
                .lineLimit(2)
        }
        // Only deep-link when we actually have a story. Otherwise
        // tapping would route to `spool://story/0`, which surfaces
        // a dead-end "story not found" page. flatMap collapses the
        // double-optional (URL?? -> URL?) that a plain `map` would
        // produce.
        .widgetURL(story.flatMap { URL(string: "spool://story/\($0.id)") })
    }
}

// MARK: - Empty state shared across families

/// Rendered when the timeline provider returned with no stories —
/// either first-launch before the network call returned, or a
/// failed refresh leaving the previous entry stale.
private struct WidgetEmptyState: View {
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: isStale ? "wifi.exclamationmark" : "sparkles")
                .font(.title3)
                .foregroundStyle(isStale ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
            Text(isStale ? "Couldn't refresh" : "Loading top stories…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            if isStale {
                Text("The widget will try again automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
