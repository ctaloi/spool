import SwiftUI

/// Skeleton placeholder shown in either summary section before its
/// first words land. Three lines with descending right padding so the
/// silhouette reads as "text loading" rather than "loading bars."
struct SummaryPlaceholderLines: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.tertiary)
                    .frame(height: 10)
                    .frame(maxWidth: .infinity)
                    .padding(.trailing, CGFloat([0, 60, 120][index]))
            }
        }
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
