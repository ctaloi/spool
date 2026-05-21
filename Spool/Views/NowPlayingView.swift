import SwiftUI
import AVFoundation
import UIKit

/// Full-screen now-playing sheet for the Spool. Big controls,
/// scrubber, and the spoken summary
/// text scrolling alongside the audio with the current sentence
/// highlighted.
///
/// Presented by tapping the mini-player. Dismisses with the
/// standard sheet drag-down gesture.
struct NowPlayingView: View {
    @EnvironmentObject private var player: SpoolPlayer
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.advancedVoiceTipDismissed) private var voiceTipDismissed: Bool = false
    /// Captures the slider's value while the user is mid-drag so the
    /// 10 Hz timer-driven `currentTime` updates don't yank the thumb
    /// back to the live position before they release. nil when not
    /// scrubbing.
    @State private var scrubDragValue: TimeInterval? = nil

    var body: some View {
        NavigationStack {
            if let current = player.currentItem {
                content(for: current)
            } else {
                ContentUnavailableView(
                    "Nothing Playing",
                    systemImage: "waveform.slash",
                    description: Text("Add stories to your spool, then tap Play.")
                )
            }
        }
    }

    @ViewBuilder
    private func content(for current: SpooledStory) -> some View {
        VStack(spacing: 0) {
            // Header — title, host, queue position.
            VStack(alignment: .leading, spacing: 6) {
                if let host = current.urlString.flatMap(URL.init(string:))?.host {
                    Text(host.replacingOccurrences(of: "www.", with: ""))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .textCase(.uppercase)
                        .tracking(0.6)
                }
                Text(current.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 12)

            if shouldShowVoiceTip {
                voiceTipBanner
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Text view — full summary, current sentence highlighted,
            // auto-scrolls to keep the spoken sentence in view.
            spokenTextScroller
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Progress + controls.
            playbackControls
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
        }
        .navigationTitle("Now Playing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: - Spoken text scroller

    /// Extracted into its own View so SwiftUI can short-circuit
    /// re-renders when `script` and `location` haven't changed.
    /// Previously, this scroller lived as a computed property on
    /// NowPlayingView — every 10 Hz `player.currentTime` tick made
    /// the parent body re-execute, which forced the ForEach to
    /// rebuild every Text view and produced the choppy scroll feel
    /// the user reported.
    private var spokenTextScroller: some View {
        SpokenTextScroller(
            script: player.currentScript,
            spokenLocation: player.currentSpokenLocation,
            spokenLength: player.currentSpokenLength
        )
        .equatable()
    }

    // MARK: - Controls

    @ViewBuilder
    private var playbackControls: some View {
        VStack(spacing: 16) {
            // Scrubber for cached audio; fall back to a read-only
            // progress bar on the live-synth path (no seek API).
            if player.currentDuration > 0 {
                Slider(
                    value: Binding(
                        get: { scrubDragValue ?? player.currentTime },
                        set: { scrubDragValue = $0 }
                    ),
                    in: 0...player.currentDuration,
                    onEditingChanged: { editing in
                        if !editing, let target = scrubDragValue {
                            player.seek(to: target)
                            scrubDragValue = nil
                        }
                    }
                )
                .tint(Theme.accent)
            } else {
                ProgressView(value: player.currentProgress)
                    .tint(Theme.accent)
                    .progressViewStyle(.linear)
            }

            HStack {
                Text(currentProgressLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(queueProgressLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Transport row.
            HStack(spacing: 32) {
                Button {
                    player.previous()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                .accessibilityLabel("Previous")

                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 60))
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(player.state == .playing ? "Pause" : "Play")

                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                .accessibilityLabel("Next")
                .disabled(!hasNext)
            }
            .tint(Theme.accent)
            .padding(.vertical, 4)

            // Active voice — quiet readout that doubles as a tap
            // target into the voice picker, so users can swap voices
            // without leaving the now-playing screen.
            if let label = voiceLabel {
                NavigationLink {
                    VoicePickerView()
                        .environmentObject(player)
                } label: {
                    HStack(spacing: 8) {
                        Text("Voice")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(label)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var currentProgressLabel: String {
        // Cached-audio path: show mm:ss / mm:ss like a podcast player.
        if player.currentDuration > 0 {
            let displayed = scrubDragValue ?? player.currentTime
            return "\(formatSeconds(displayed)) / \(formatSeconds(player.currentDuration))"
        }
        // Live-synth path: only have a 0…1 fraction.
        let pct = Int((player.currentProgress * 100).rounded())
        return "\(pct)%"
    }

    private func formatSeconds(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var queueProgressLabel: String {
        guard let i = player.currentIndex else { return "" }
        return "\(i + 1) of \(player.queue.count)"
    }

    private var hasNext: Bool {
        guard let i = player.currentIndex else { return false }
        return i + 1 < player.queue.count
    }

    /// "Samantha · Premium" formatted readout of the voice the player
    /// will use for the next utterance. `nil` only on the unusual path
    /// where the system reports zero installed voices for the user's
    /// language.
    private var voiceLabel: String? {
        guard let voice = player.bestVoice() else { return nil }
        let q: String
        switch voice.quality {
        case .premium:  q = "Premium"
        case .enhanced: q = "Enhanced"
        case .default:  q = "Default"
        @unknown default: q = "Default"
        }
        return "\(voice.name) · \(q)"
    }

    // MARK: - Voice-quality onboarding tip

    /// Surface the tip only when the active voice is the small default
    /// tier AND the user hasn't already dismissed or acted on it. The
    /// `hasAdvancedVoice` check re-evaluates on every render so the
    /// banner disappears the moment the user installs an Enhanced voice
    /// and returns to the app.
    private var shouldShowVoiceTip: Bool {
        !voiceTipDismissed && !player.hasAdvancedVoice
    }

    @ViewBuilder
    private var voiceTipBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "speaker.wave.2.bubble")
                .font(.title3)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Better voice available")
                    .font(.subheadline.weight(.semibold))
                Text("You're using the default voice. Settings → Accessibility → Spoken Content → Voices has higher-quality downloads.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Settings") {
                    openVoiceSettings()
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .tint(Theme.accent)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.easeInOut(duration: Theme.AnimationDuration.quick)) {
                    voiceTipDismissed = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dismiss voice tip")
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(
            Color(.secondarySystemBackground),
            in: .rect(cornerRadius: Theme.CornerRadius.card, style: .continuous)
        )
    }

    /// Best-effort deep link to the Voices settings screen. iOS does
    /// not expose a public API for this — the private `App-prefs:`
    /// URL scheme lands on the Accessibility root, which is one
    /// navigation step away from Voices. Falls back to opening this
    /// app's own Settings page if the private URL is unavailable.
    /// Tapping Open Settings dismisses the tip either way, since the
    /// user has now been pointed at the right place.
    private func openVoiceSettings() {
        withAnimation(.easeInOut(duration: Theme.AnimationDuration.quick)) {
            voiceTipDismissed = true
        }
        let fallback = URL(string: UIApplication.openSettingsURLString)
        if let prefs = URL(string: "App-prefs:ACCESSIBILITY") {
            UIApplication.shared.open(prefs, options: [:]) { success in
                if !success, let fallback {
                    UIApplication.shared.open(fallback)
                }
            }
        } else if let fallback {
            UIApplication.shared.open(fallback)
        }
    }

}

/// Sentence-by-sentence reading view with word-level highlighting,
/// isolated from the player's high-frequency `currentTime` updates.
/// Only re-renders when the script, the spoken-character location, or
/// the current word's length actually change, so scroll gestures
/// don't fight a fresh-body-per-tick re-layout.
private struct SpokenTextScroller: View, Equatable {
    let script: String
    let spokenLocation: Int
    let spokenLength: Int

    @State private var sentences: [Sentence] = []
    @State private var currentSentenceIndex: Int = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(sentences.enumerated()), id: \.offset) { idx, sentence in
                        Text(attributedSentence(at: idx, sentence: sentence))
                            .font(Theme.Typography.body)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(idx)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
            }
            // Splitting the script is non-trivial; do it once per
            // script change, not on every parent body re-evaluation.
            .task(id: script) {
                sentences = Sentence.split(script)
                currentSentenceIndex = Sentence.indexContaining(
                    location: spokenLocation,
                    in: sentences
                )
            }
            // Cheap per-tick: a single linear scan of the cached
            // sentence array. Auto-scrolls to the active sentence
            // only when it actually advances (skips redundant
            // animations during user scrolling).
            .onChange(of: spokenLocation) { _, loc in
                let new = Sentence.indexContaining(location: loc, in: sentences)
                guard new != currentSentenceIndex else { return }
                currentSentenceIndex = new
                withAnimation(.easeInOut(duration: Theme.AnimationDuration.slow)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
    }

    /// Builds the per-sentence AttributedString. Past sentences fade
    /// to secondary; upcoming sentences fade further. The active
    /// sentence renders in primary color with the currently-spoken
    /// word in bold + brand accent — the karaoke-style highlight the
    /// user asked for.
    private func attributedSentence(at idx: Int, sentence: Sentence) -> AttributedString {
        var attr = AttributedString(sentence.text)
        attr.foregroundColor = baseColor(for: idx)
        guard idx == currentSentenceIndex,
              spokenLength > 0
        else { return attr }

        // Map the script-relative spoken range onto this sentence's
        // local string. `Sentence.text` is the trimmed sentence; its
        // characters start at `sentence.start` in the original
        // script (modulo the leading whitespace we trimmed for
        // display). Find the word's offset in the trimmed text by
        // shifting from script-space.
        let scriptStart = spokenLocation
        let scriptEnd = spokenLocation + spokenLength
        guard scriptStart < sentence.end, scriptEnd > sentence.start else { return attr }

        // Clamp to sentence bounds, then shift to local indices.
        let localStart = max(0, scriptStart - sentence.start)
        let localEnd = min(sentence.text.utf16.count, scriptEnd - sentence.start)
        guard localStart < localEnd else { return attr }

        // Apply the bold + accent attribute to that substring.
        let utf16 = sentence.text.utf16
        guard let start16 = utf16.index(utf16.startIndex, offsetBy: localStart, limitedBy: utf16.endIndex),
              let end16 = utf16.index(utf16.startIndex, offsetBy: localEnd, limitedBy: utf16.endIndex),
              let lower = String.Index(start16, within: sentence.text),
              let upper = String.Index(end16, within: sentence.text),
              let attrRange = Range(NSRange(lower..<upper, in: sentence.text), in: attr)
        else { return attr }
        attr[attrRange].foregroundColor = Theme.accent
        attr[attrRange].font = Theme.Typography.body.weight(.semibold)
        return attr
    }

    /// Base foreground for a sentence based on its position vs. the
    /// active read. Tri-state: bright current, dim past, dimmer
    /// upcoming. The "upcoming" color is a fixed gray (instead of
    /// `.secondary.opacity(_:)`) so dark mode doesn't over-brighten
    /// the unread portion.
    private func baseColor(for idx: Int) -> Color {
        if idx == currentSentenceIndex { return .primary }
        if idx < currentSentenceIndex { return .secondary }
        return Color(white: Theme.Opacity.upcomingText)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        // Equatable lets SwiftUI skip a body re-evaluation when the
        // inputs haven't changed — the critical win that stops the
        // 10 Hz timer from bleeding into the scroller's redraw path.
        lhs.script == rhs.script
            && lhs.spokenLocation == rhs.spokenLocation
            && lhs.spokenLength == rhs.spokenLength
    }
}
