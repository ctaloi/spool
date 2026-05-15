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

    @State private var thumbnail: UIImage?
    @State private var thumbnailLookupComplete = false
    @State private var accentColor: Color?
    @AppStorage(SettingsKeys.showThumbnails) private var showThumbnails: Bool = true

    /// External URL for the story, if any. Ask HN / Show HN / Tell HN
    /// text posts have no URL and skip the thumbnail entirely.
    private var articleURL: URL? {
        guard let s = story.url else { return nil }
        return URL(string: s)
    }

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

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
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
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if showThumbnails, articleURL != nil {
                        thumbnailView
                    }
                }

                metaLine
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .opacity(isRead ? 0.6 : 1.0)
        // iPad / Mac Catalyst: subtle highlight when hovered.
        // No effect on iPhone.
        .hoverEffect(.highlight)
        // Drag the story out to Safari / Notes / Mail / Messages.
        // Most receivers know what to do with a URL; pure-text targets
        // get a sensible fallback constructed inside `dragText`.
        .draggable(articleURL ?? URL(string: "https://news.ycombinator.com/item?id=\(story.id)")!) {
            dragPreview
        }
        .task(id: articleURL) {
            // Skip network work entirely when the toggle is off — no
            // wasted HTML fetches for thumbnails we'd never render.
            guard showThumbnails else { return }
            await loadThumbnail()
        }
    }

    // MARK: - Thumbnail

    /// Square thumbnail: the OG image if we found one, otherwise a quiet
    /// letterform fallback (first letter of the domain on a soft accent
    /// background). Loading is lazy and silent — no spinner.
    @ViewBuilder
    private var thumbnailView: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [Theme.accentSoft, Color(.tertiarySystemFill)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                if thumbnailLookupComplete {
                    Text(fallbackLetter)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                // Per-story accent color extracted from the OG image —
                // each row carries a hint of its own brand identity.
                .stroke(thumbnailStrokeColor, lineWidth: accentColor == nil ? 0.5 : 1)
        )
        .animation(.easeInOut(duration: 0.25), value: thumbnail != nil)
        .animation(.easeInOut(duration: 0.3), value: accentColor)
    }

    private var thumbnailStrokeColor: Color {
        if let accentColor {
            return accentColor.opacity(0.55)
        }
        return Color(.separator).opacity(0.4)
    }

    /// Mini card shown under the user's finger while dragging the row
    /// to another app. The system handles the lift / settle animation;
    /// this just needs to be a small, glanceable preview.
    private var dragPreview: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.richtext")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(story.title ?? "(no title)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let host = story.host {
                    Text(host)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var fallbackLetter: String {
        if let host = story.host {
            return String(host.prefix(1)).uppercased()
        }
        if let first = story.title?.first {
            return String(first).uppercased()
        }
        return "•"
    }

    private func loadThumbnail() async {
        guard let url = articleURL else {
            thumbnail = nil
            accentColor = nil
            thumbnailLookupComplete = true
            return
        }
        // Reset state when the URL changes (row reused for a different story).
        thumbnail = nil
        accentColor = nil
        thumbnailLookupComplete = false
        do {
            let preview = try await ArticleFetcher.shared.fetchPreview(from: url)
            guard !Task.isCancelled else { return }
            if let imageURL = preview.imageURL {
                let image = try await ImageFetcher.shared.image(for: imageURL)
                guard !Task.isCancelled else { return }
                self.thumbnail = image
                // Extract the per-story accent in the background; we
                // don't need to block the row on it.
                let extracted = await DominantColor.shared.extract(from: image, url: imageURL)
                guard !Task.isCancelled else { return }
                if let extracted {
                    self.accentColor = Color(extracted)
                }
            }
        } catch {
            // Swallow — fallback letterform handles the empty state and
            // we don't want network noise in the row UI.
        }
        thumbnailLookupComplete = true
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
                Text("\(story.score ?? 0)")
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(story.score ?? 0)))
            }

            metaSeparator

            Text("^[\(story.descendants ?? 0) comment](inflect: true)")
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(story.descendants ?? 0)))

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
