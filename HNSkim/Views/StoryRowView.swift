import SwiftUI

struct StoryRowView: View {
    let rank: Int?
    let story: HNItem
    var context: String? = nil
    var isRead: Bool = false
    var isSaved: Bool = false

    /// Rank column width grows with Dynamic Type so 2- and 3-digit ranks
    /// don't clip at larger reading sizes.
    @ScaledMetric(relativeTo: .footnote) private var rankColumnWidth: CGFloat = 24

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            rankMarker
                .frame(width: rankColumnWidth, alignment: .trailing)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                if let badge = typeBadge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accentSoft, in: .capsule)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(story.title ?? "(no title)")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if isSaved && rank != nil {
                        Image(systemName: "bookmark.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                    }
                }

                if let host = story.host {
                    HStack(spacing: 3) {
                        Image(systemName: "link")
                            .font(.caption2)
                        Text(host)
                            .font(.footnote)
                    }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                metaLine
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .opacity(isRead ? 0.6 : 1.0)
    }

    @ViewBuilder
    private var rankMarker: some View {
        if let rank {
            Text("\(rank)")
                .font(Theme.Typography.scoreCompact)
                .foregroundStyle(Theme.accent)
        } else {
            Image(systemName: "bookmark.fill")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.accent)
        }
    }

    /// Single quiet meta line: score · comments · author · time.
    private var metaLine: some View {
        HStack(spacing: 0) {
            if let context {
                Text(context)
                    .layoutPriority(-1)
                metaSeparator
            }

            metaItem {
                Image(systemName: "arrow.up")
                Text("\(story.score ?? 0)").monospacedDigit()
            }

            metaSeparator

            Text("^[\(story.descendants ?? 0) comment](inflect: true)")
                .monospacedDigit()

            if let by = story.by {
                metaSeparator
                Text(by)
                    .layoutPriority(-1)
            }

            if let date = story.date {
                metaSeparator
                Text(date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
            }

            Spacer(minLength: 0)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    /// One inline meta cluster (icon + text) that stays together.
    @ViewBuilder
    private func metaItem<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 4) {
            content()
        }
        .fixedSize()
    }

    private var metaSeparator: some View {
        Text(verbatim: "  ·  ")
            .foregroundStyle(.tertiary)
            .fixedSize()
    }

    private var typeBadge: String? {
        switch story.type {
        case "job": return "JOB"
        case "story":
            if let t = story.title?.lowercased() {
                if t.hasPrefix("ask hn") { return "ASK" }
                if t.hasPrefix("show hn") { return "SHOW" }
                if t.hasPrefix("tell hn") { return "TELL" }
                if t.hasPrefix("launch hn") { return "LAUNCH" }
            }
            return nil
        default: return nil
        }
    }
}
