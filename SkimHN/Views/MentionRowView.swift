import SwiftUI

/// One row in the Mentions feed. Pairs the user's original comment
/// (faded, "you wrote") with the incoming reply (primary, "[author]
/// replied"), under the story title that hosts the thread.
///
/// Layout is deliberately quiet — no thumbnail, no rank, just enough
/// scaffolding to triangulate which thread the exchange came from.
/// Tap routes to the host story (Phase 1: no scroll-anchor; the user
/// lands at the top of the comment tree and reads down).
struct MentionRowView: View {
    let record: MentionRecord
    let isUnread: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            storyTitleEyebrow

            yourComment

            replyBlock
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var storyTitleEyebrow: some View {
        HStack(spacing: 6) {
            if isUnread {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            Text(record.parentComment.storyTitle ?? "Story")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Text(timeAgo)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    private var yourComment: some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(Color(.separator).opacity(0.5))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("You wrote")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(.tertiary)
                if let text = record.parentComment.text, !text.isEmpty {
                    HTMLText(html: text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                } else {
                    Text("(no text)")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var replyBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.accent)
                Text(record.reply.by ?? "Someone")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("replied")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let text = record.reply.text, !text.isEmpty {
                HTMLText(html: text)
                    .font(Theme.Typography.body)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var timeAgo: String {
        guard let ts = record.reply.time else { return "" }
        return Date(timeIntervalSince1970: ts).formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
    }
}
