import SwiftUI

/// Skeleton placeholder shown in either summary section before its
/// first words land. Three lines with descending right padding so the
/// silhouette reads as "text loading", overlaid with a traveling
/// gradient shimmer — the canonical skeleton-screen pattern.
///
/// Implementation: each line is a tertiary-fill capsule with a soft
/// white highlight gradient masked to its bounds. The highlight's
/// x-offset animates from -1 → +1 (in width multiples) with
/// `.repeatForever(autoreverses: false)`, producing the "sweep". Each
/// line's animation phase is offset by a small delay so the wave
/// ripples down the stack instead of all three lines flashing in
/// lockstep.
struct SummaryPlaceholderLines: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                ShimmerLine(
                    trailingPadding: CGFloat([0, 60, 120][index]),
                    delay: Double(index) * 0.18
                )
            }
        }
        .accessibilityHidden(true)
    }
}

/// One shimmering skeleton line. Owns its own phase so each line in
/// the stack can sweep with an offset delay without us having to
/// thread a parent animation state.
private struct ShimmerLine: View {
    let trailingPadding: CGFloat
    let delay: Double
    @State private var phase: CGFloat = -1.2

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(.tertiary)
            .frame(height: 10)
            .frame(maxWidth: .infinity)
            .padding(.trailing, trailingPadding)
            .overlay(
                GeometryReader { proxy in
                    LinearGradient(
                        stops: [
                            .init(color: .clear,                       location: 0),
                            .init(color: Color.white.opacity(0.55),    location: 0.5),
                            .init(color: .clear,                       location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.45)
                    .offset(x: phase * proxy.size.width)
                    .blendMode(.plusLighter)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                // The shimmer overlay is purely decorative — no need to
                // anti-alias against the trailing padding region.
                .padding(.trailing, trailingPadding)
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                        .delay(delay)
                ) {
                    phase = 1.2
                }
            }
    }
}

/// "AI is generating" indicator used as the tail beneath in-flight
/// summary prose. A 2pt-tall capsule with a soft accent-color
/// highlight gradient that sweeps continuously left→right, like a
/// tracer of light running across the bottom of the card. Reads as
/// "the model is still writing" without competing with the header
/// sparkle pulse.
struct StreamingAuroraTrail: View {
    @State private var phase: CGFloat = -1.2

    var body: some View {
        Capsule(style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .frame(height: 2)
            .overlay(
                GeometryReader { proxy in
                    LinearGradient(
                        stops: [
                            .init(color: .clear,                            location: 0),
                            .init(color: Theme.accent.opacity(0.9),         location: 0.5),
                            .init(color: .clear,                            location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.32)
                    .offset(x: phase * proxy.size.width)
                }
                .clipShape(Capsule(style: .continuous))
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 1.6)
                        .repeatForever(autoreverses: false)
                ) {
                    phase = 1.2
                }
            }
            .accessibilityLabel("Generating")
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

/// Primary CTA inside the unified summary card and a fallback
/// affordance in error states. Uses iOS 26's `.glass` button style —
/// the system handles capsule shape, translucent background, pressed
/// state, and accessibility scaling. We just provide the label + tint.
struct OutlineActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .tint(Theme.accent)
    }
}

/// Icon-only Liquid Glass button — used for the "Summarize Again"
/// refresh affordance and other small icon actions. Same native
/// `.glass` style; the symbol bounces on each tap via tapCount.
struct OutlineIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void
    @State private var tapCount = 0

    var body: some View {
        Button {
            tapCount += 1
            action()
        } label: {
            Image(systemName: systemImage)
                .symbolEffect(.rotate, value: tapCount)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .tint(Theme.accent)
        .accessibilityLabel(accessibilityLabel)
    }
}
