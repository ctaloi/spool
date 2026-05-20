import SwiftUI

/// Empty state for the detail column on iPad three-pane. Re-uses the
/// app icon's pill-bar mark (subtler tinting than the launch splash)
/// so the empty state still feels like Spool — not a generic
/// `ContentUnavailableView`.
struct DetailPlaceholderView: View {
    private let bars: [(width: CGFloat, color: Color)] = [
        (96, Theme.accent.opacity(0.65)),
        (72, Color(.label).opacity(0.32)),
        (48, Color(.label).opacity(0.18)),
    ]

    var body: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    Capsule(style: .continuous)
                        .fill(bar.color)
                        .frame(width: bar.width, height: 14)
                }
            }
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Pick a story")
                    .font(.system(size: 22, weight: .light, design: .default))
                    .foregroundStyle(.primary)
                Text("Stories you tap on the left will open here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
