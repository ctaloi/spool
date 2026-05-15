import SwiftUI

/// Skeleton placeholder shown in either summary section before its
/// first words land. Three lines with descending right padding so the
/// silhouette reads as "text loading" rather than "loading bars."
///
/// Lines breathe gently out of phase so the placeholder looks alive
/// while the model warms up. The animation is set to a long, slow
/// easeInOut so it never crosses into "this is broken / loading
/// forever" territory.
struct SummaryPlaceholderLines: View {
    @State private var animating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.tertiary)
                    .frame(height: 10)
                    .frame(maxWidth: .infinity)
                    .padding(.trailing, CGFloat([0, 60, 120][index]))
                    .opacity(animating ? 0.45 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.1)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .accessibilityHidden(true)
        .onAppear { animating = true }
    }
}

/// Three small accent dots pulsing out of phase. Used as a "still
/// generating" tail below in-flight summary prose — gives the user
/// a clear "we're working" signal that doesn't compete with the
/// header sparkle pulse.
struct StreamingDots: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.accent.opacity(0.55))
                    .frame(width: 5, height: 5)
                    .scaleEffect(animating ? 1.0 : 0.55)
                    .opacity(animating ? 1.0 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Generating")
        .onAppear { animating = true }
    }
}

/// Editorial three-dot fleuron used between the Article and
/// Discussion sections inside the unified summary card. Renders as a
/// hairline–fleuron–hairline composition so the break reads as a
/// section divider, not as content.
struct SummarySectionDivider: View {
    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color(.separator).opacity(0.45))
                .frame(height: 0.5)
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Theme.accent.opacity(0.5))
                        .frame(width: 3, height: 3)
                }
            }
            Rectangle()
                .fill(Color(.separator).opacity(0.45))
                .frame(height: 0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .accessibilityHidden(true)
    }
}

/// Shared outline-only action button — the un-tinted-fill stroked
/// capsule used as the primary CTA inside the unified summary card,
/// and as a fallback affordance in error states.
struct OutlineActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Theme.accent.opacity(0.55), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Capsule(style: .continuous))
    }
}

/// Icon-only outline variant — same stroked-circle look as
/// `OutlineActionButton`, used for the "Summarize Again" refresh
/// affordance and other small icon actions inside summary cards.
struct OutlineIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .overlay(
                    Circle().stroke(Theme.accent.opacity(0.55), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
