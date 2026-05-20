import SwiftUI

/// Persistent bottom-edge mini player. Renders whenever the
/// shared `SpoolPlayer` has an item playing or paused, across
/// every screen (sidebar, list, detail). Hidden in idle state.
///
/// Layout mirrors Apple Music's mini bar: now-playing title on the
/// left, play/pause + next on the right, Liquid Glass backdrop,
/// hairline separator at the top. Tap to expand — currently a
/// no-op-but-haptic placeholder for a future full-screen now-
/// playing surface.
struct SpoolMiniPlayer: View {
    @EnvironmentObject private var player: SpoolPlayer
    @State private var showNowPlaying = false

    var body: some View {
        if player.isActive, let current = player.currentItem {
            miniBar(current: current)
                .onTapGesture {
                    showNowPlaying = true
                }
                .sheet(isPresented: $showNowPlaying) {
                    NowPlayingView()
                        .environmentObject(player)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
        }
    }

    @ViewBuilder
    private func miniBar(current: SpooledStory) -> some View {
        HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.body)
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(
                        .variableColor.iterative.reversing,
                        options: .repeating,
                        isActive: player.state == .playing
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(current.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(progressLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                Spacer(minLength: 4)

                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.state == .playing ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .tint(Theme.accent)
                .accessibilityLabel(player.state == .playing ? "Pause" : "Resume")

                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .tint(Theme.accent)
                .accessibilityLabel("Next")
                .disabled(!hasNext)

                Button {
                    player.stop()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .tint(.secondary)
                .accessibilityLabel("Stop")
            }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(.separator).opacity(0.4))
                .frame(height: 0.5)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var progressLabel: String {
        guard let index = player.currentIndex else { return "" }
        let count = player.queue.count
        return "\(index + 1) of \(count)"
    }

    private var hasNext: Bool {
        guard let i = player.currentIndex else { return false }
        return i + 1 < player.queue.count
    }
}
