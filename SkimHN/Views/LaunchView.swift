import SwiftUI

/// First-frame branded splash. Mirrors the app icon's three-pill mark
/// and staggers each bar in for a quiet sense of build-up — long enough
/// to register as intentional, short enough not to delay the user. The
/// main app mounts and starts fetching data underneath, so this is
/// buffered brand presence, not extra latency.
struct LaunchView: View {
    @State private var visibleBars: Int = 0
    @State private var wordmarkVisible: Bool = false

    private let bars: [(width: CGFloat, color: Color)] = [
        (144, Theme.accent),
        (108, Color(.label).opacity(0.55)),
        ( 72, Color(.label).opacity(0.28)),
    ]

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { index, bar in
                        Capsule(style: .continuous)
                            .fill(bar.color)
                            .frame(width: bar.width, height: 18)
                            .offset(x: index < visibleBars ? 0 : -36)
                            .opacity(index < visibleBars ? 1 : 0)
                    }
                }

                Text("SkimHN")
                    .font(.system(size: 22, weight: .light, design: .default))
                    .foregroundStyle(.primary)
                    .opacity(wordmarkVisible ? 1 : 0)
            }
        }
        .task {
            // Stagger the three bars in, then fade the wordmark.
            for _ in 0..<bars.count {
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(.easeOut(duration: 0.32)) {
                    visibleBars += 1
                }
            }
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.easeInOut(duration: 0.42)) {
                wordmarkVisible = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SkimHN")
    }
}
