import SwiftUI
import AVFoundation

/// Full-screen now-playing sheet for the Listen queue. Big controls,
/// read-only progress bar, speed picker, and the spoken summary
/// text scrolling alongside the audio with the current sentence
/// highlighted.
///
/// Presented by tapping the mini-player. Dismisses with the
/// standard sheet drag-down gesture.
struct NowPlayingView: View {
    @EnvironmentObject private var player: ReadLaterPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let current = player.currentItem {
                content(for: current)
            } else {
                ContentUnavailableView(
                    "Nothing Playing",
                    systemImage: "waveform.slash",
                    description: Text("Tap Play in the Listen queue to start.")
                )
            }
        }
    }

    @ViewBuilder
    private func content(for current: ReadLaterStory) -> some View {
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

            // Text view — full summary, current sentence highlighted,
            // auto-scrolls to keep the spoken sentence in view.
            spokenTextScroller
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Progress + controls.
            playbackControls
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
        }
        .navigationTitle("Now Listening")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: - Spoken text scroller

    /// Splits the spoken script into sentence-sized rows so each
    /// sentence gets its own ScrollView anchor. Without this, the
    /// outer scrollTo can't actually navigate WITHIN one giant Text
    /// view — every "scroll to current" would be a no-op.
    private var sentences: [Sentence] {
        Sentence.split(player.currentScript)
    }

    /// Index of the sentence currently being spoken. Drives both
    /// the highlight style and the scroll target.
    private var currentSentenceIndex: Int {
        Sentence.indexContaining(
            location: player.currentSpokenLocation,
            in: sentences
        )
    }

    @ViewBuilder
    private var spokenTextScroller: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(sentences.enumerated()), id: \.offset) { idx, sentence in
                        Text(sentence.text)
                            .font(Theme.Typography.body)
                            .foregroundStyle(foreground(for: idx))
                            .fontWeight(idx == currentSentenceIndex ? .semibold : .regular)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(idx)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
            }
            .onChange(of: currentSentenceIndex) { _, new in
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
    }

    /// Tri-state foreground: bright for the current sentence, dim
    /// for spoken/upcoming. Gives a clear focal point without the
    /// rest of the text disappearing.
    private func foreground(for idx: Int) -> Color {
        if idx == currentSentenceIndex { return .primary }
        if idx < currentSentenceIndex { return .secondary }
        return Color(white: 0.45)
    }

    // MARK: - Controls

    @ViewBuilder
    private var playbackControls: some View {
        VStack(spacing: 16) {
            // Read-only progress bar within the current item.
            ProgressView(value: player.currentProgress)
                .tint(Theme.accent)
                .progressViewStyle(.linear)

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

            // Speed picker.
            HStack(spacing: 8) {
                Text("Speed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Speed", selection: speedBinding) {
                    Text("0.5×").tag(Speed.half)
                    Text("1×").tag(Speed.normal)
                    Text("1.5×").tag(Speed.oneAndHalf)
                    Text("2×").tag(Speed.double)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
        }
    }

    private var currentProgressLabel: String {
        let pct = Int((player.currentProgress * 100).rounded())
        return "\(pct)%"
    }

    private var queueProgressLabel: String {
        guard let i = player.currentIndex else { return "" }
        return "\(i + 1) of \(player.queue.count)"
    }

    private var hasNext: Bool {
        guard let i = player.currentIndex else { return false }
        return i + 1 < player.queue.count
    }

    // MARK: - Sentence splitter

    /// One sentence-shaped chunk of the spoken script with its
    /// character-range anchors. Lets us render each sentence as a
    /// separate Text row (so ScrollViewReader's scrollTo actually
    /// navigates) AND figure out which one is currently being read
    /// from the synth's char-range delegate output.
    private struct Sentence {
        let text: String
        let start: Int
        let end: Int

        /// Walk the script char-by-char, cutting on `.!?` or end
        /// of string. Whitespace at the head of each sentence is
        /// trimmed for display but the original offsets are
        /// preserved so we can match the speech location.
        static func split(_ script: String) -> [Sentence] {
            guard !script.isEmpty else { return [] }
            var result: [Sentence] = []
            let chars = Array(script)
            var segmentStart = 0
            for (i, char) in chars.enumerated() {
                let atEnd = i == chars.count - 1
                if ".!?".contains(char) || atEnd {
                    let endExclusive = i + 1
                    let raw = String(chars[segmentStart..<endExclusive])
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        result.append(Sentence(
                            text: trimmed,
                            start: segmentStart,
                            end: endExclusive
                        ))
                    }
                    segmentStart = endExclusive
                }
            }
            return result
        }

        /// Returns the index of the sentence containing the given
        /// character location, or 0 / last as a safe fallback.
        static func indexContaining(location: Int, in sentences: [Sentence]) -> Int {
            guard !sentences.isEmpty else { return 0 }
            for (idx, sent) in sentences.enumerated() {
                if location < sent.end { return idx }
            }
            return sentences.count - 1
        }
    }

    // MARK: - Speed picker plumbing

    private enum Speed: Hashable {
        case half, normal, oneAndHalf, double

        var rate: Float {
            switch self {
            case .half:        return AVSpeechUtteranceDefaultSpeechRate * 0.7
            case .normal:      return AVSpeechUtteranceDefaultSpeechRate
            case .oneAndHalf:  return AVSpeechUtteranceDefaultSpeechRate * 1.5
            case .double:      return AVSpeechUtteranceDefaultSpeechRate * 2.0
            }
        }

        static func from(rate: Float) -> Speed {
            let normalized = rate / AVSpeechUtteranceDefaultSpeechRate
            if normalized <= 0.8 { return .half }
            if normalized < 1.2  { return .normal }
            if normalized < 1.75 { return .oneAndHalf }
            return .double
        }
    }

    private var speedBinding: Binding<Speed> {
        Binding(
            get: { Speed.from(rate: player.rate) },
            set: { player.rate = $0.rate }
        )
    }
}
