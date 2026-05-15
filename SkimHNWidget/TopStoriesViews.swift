import WidgetKit
import SwiftUI

/// Root dispatcher — picks the right size view from the widget
/// family. Each size renders the same `TopStoriesEntry` data
/// differently, with deep-links into the app via skimhn://story/<id>.
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

// MARK: - Small

/// 1 story, big title, score below. Tapping anywhere opens that story.
private struct SmallStoryView: View {
    let entry: TopStoriesEntry

    var body: some View {
        if let story = entry.stories.first {
            VStack(alignment: .leading, spacing: 6) {
                Text("Y").font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.orange)
                    .frame(width: 22, height: 22)
                    .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                Text(story.title ?? "(no title)")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(4)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                metaLine(story)
            }
            .widgetURL(URL(string: "skimhn://story/\(story.id)"))
        } else {
            emptyView
        }
    }

    @ViewBuilder
    private func metaLine(_ story: HNItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up").font(.caption2)
            Text("\(story.score ?? 0)")
                .font(.caption.monospacedDigit())
            if let descendants = story.descendants {
                Text("·").foregroundStyle(.tertiary)
                Image(systemName: "bubble.left").font(.caption2)
                Text("\(descendants)").font(.caption.monospacedDigit())
            }
        }
        .foregroundStyle(.secondary)
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.secondary)
            Text(entry.isStale ? "Couldn't refresh" : "Loading…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Medium

/// 3 stories, rank + title + score. Each row deep-links.
private struct MediumStoryView: View {
    let entry: TopStoriesEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(entry.stories.prefix(3).enumerated()), id: \.element.id) { idx, story in
                Link(destination: URL(string: "skimhn://story/\(story.id)")!) {
                    storyRow(rank: idx + 1, story: story)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func storyRow(rank: Int, story: HNItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(rank).")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.orange)
                .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(story.title ?? "(no title)")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Label("\(story.score ?? 0)", systemImage: "arrow.up")
                    Label("\(story.descendants ?? 0)", systemImage: "bubble.left")
                }
                .font(.caption2.monospacedDigit())
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Large

/// 6 stories with rank + title. Less metadata per row so titles get
/// the room they need to be readable.
private struct LargeStoryView: View {
    let entry: TopStoriesEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Top on HN")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(entry.date, format: .dateTime.hour().minute())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)

            ForEach(Array(entry.stories.prefix(6).enumerated()), id: \.element.id) { idx, story in
                Link(destination: URL(string: "skimhn://story/\(story.id)")!) {
                    row(rank: idx + 1, story: story)
                }
                if idx < 5 {
                    Divider().opacity(0.4)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func row(rank: Int, story: HNItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(rank)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.orange)
                .frame(width: 16, alignment: .trailing)
                .monospacedDigit()
            Text(story.title ?? "(no title)")
                .font(.system(size: 13))
                .lineLimit(2)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(story.score ?? 0)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
        .widgetURL(URL(string: "skimhn://story/\(story?.id ?? 0)"))
    }
}
