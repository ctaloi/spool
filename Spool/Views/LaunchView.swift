import SwiftUI

/// First-frame branded splash. Mirrors the app icon's three-pill mark
/// and staggers each bar in for a quiet sense of build-up — long enough
/// to register as intentional, short enough not to delay the user. The
/// main app mounts and starts fetching data underneath, so this is
/// buffered brand presence, not extra latency.
struct LaunchView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var visibleBars: Int = 0
    @State private var hasStartedAnimating = false

    private let bars: [(width: CGFloat, color: Color)] = [
        (144, Theme.accent),
        (108, Color(.label).opacity(0.55)),
        ( 72, Color(.label).opacity(0.28)),
    ]

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(bars.enumerated()), id: \.offset) { index, bar in
                    Capsule(style: .continuous)
                        .fill(bar.color)
                        .frame(width: bar.width, height: 18)
                        .offset(x: index < visibleBars ? 0 : -36)
                        .opacity(index < visibleBars ? 1 : 0)
                }
            }
        }
        // Gate the animation on scenePhase active so it doesn't fire
        // invisibly during iOS pre-warm or the brief window before the
        // launch image hands off to our SwiftUI scene. Without this,
        // the bars stagger in before the user can see anything and the
        // launch reads as "white screen, no animation."
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active, !hasStartedAnimating else { return }
            hasStartedAnimating = true
            Task {
                for _ in 0..<bars.count {
                    try? await Task.sleep(for: .milliseconds(140))
                    withAnimation(.easeOut(duration: Theme.AnimationDuration.standard)) {
                        visibleBars += 1
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spool")
    }
}
