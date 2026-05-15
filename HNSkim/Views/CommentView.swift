import SwiftUI

struct CommentView: View {
    let node: CommentNode
    var isCollapsed: Bool = false
    var hiddenReplyCount: Int = 0
    var canReply: Bool = false
    var onToggle: () -> Void = {}
    var onReply: () -> Void = {}
    var onSelectUser: (String) -> Void = { _ in }

    private let indentPerLevel: CGFloat = 8
    private let maxVisibleDepth = 5

    /// Stable [0, 1, ..., depth-1] array so `ForEach` doesn't hit the
    /// `Range<Int>` recycling trap inside LazyVStack: when a row gets
    /// reused for a different-depth comment, a dynamic-range ForEach
    /// fatal-errors with brk #0x1. Depth is capped so very deep threads
    /// keep a readable text column.
    private var depthLevels: [Int] {
        Array(0..<min(node.depth, maxVisibleDepth))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(depthLevels, id: \.self) { level in
                Rectangle()
                    .fill(barColor(for: level))
                    .frame(width: 2)
                    .padding(.trailing, indentPerLevel - 2)
            }

            VStack(alignment: .leading, spacing: 6) {
                Button(action: onToggle) {
                    metadataRow
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(isCollapsed ? "Expand replies" : "Collapse replies")

                if !isCollapsed {
                    HTMLText(html: node.item.text ?? "")

                    if canReply {
                        Button {
                            onReply()
                        } label: {
                            Label("Reply", systemImage: "arrowshape.turn.up.left")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.leading, node.depth == 0 ? 0 : 4)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.rowDivider)
                .frame(height: 0.5)
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 6) {
            // Author chunk — tappable to open the user profile.
            Button {
                if let by = node.item.by { onSelectUser(by) }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(authorColor)
                        .frame(width: 5, height: 5)
                    Text(node.item.by ?? "—")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(authorColor)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let date = node.item.date {
                Text("·")
                    .foregroundStyle(.tertiary)
                    .font(.footnote)
                Text(date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isCollapsed, hiddenReplyCount > 0 {
                Text("+\(hiddenReplyCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.accentSoft, in: .capsule)
            } else {
                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
            }
        }
    }

    private var authorColor: Color {
        node.depth == 0 ? Theme.accent : .primary.opacity(0.82)
    }

    private func barColor(for level: Int) -> Color {
        level == 0 ? Theme.accent.opacity(0.28) : Color.secondary.opacity(0.16)
    }
}
