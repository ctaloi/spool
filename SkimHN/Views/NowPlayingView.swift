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

    @ViewBuilder
    private var spokenTextScroller: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(highlightedText)
                    .font(Theme.Typography.body)
                    .lineSpacing(5)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .id("spoken-text")
            }
            // Each time the synth jumps ahead enough, scroll the
            // current sentence back near the top of the visible
            // area. 200 chars ≈ one paragraph-ish of pacing.
            .onChange(of: player.currentSpokenLocation / 200) { _, _ in
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo("spoken-text", anchor: .top)
                }
            }
        }
    }

    /// Builds an AttributedString that bolds the currently-spoken
    /// sentence — gives the listener a visual anchor without
    /// repainting the whole view on every word.
    private var highlightedText: AttributedString {
        var attr = AttributedString(player.currentScript)
        guard !player.currentScript.isEmpty else { return attr }

        let location = player.currentSpokenLocation
        let script = player.currentScript
        // Find the sentence containing the current speech location:
        // search backwards for ., !, or ? from `location`.
        let nsScript = script as NSString
        let upTo = min(location, nsScript.length)
        let leadingRange = NSRange(location: 0, length: upTo)
        let terminators = CharacterSet(charactersIn: ".!?")
        let leadingSubstr = nsScript.substring(with: leadingRange)
        let lastTerminator = leadingSubstr.lastIndex(where: { ".!?".contains($0) })
        let sentenceStart = lastTerminator.map { leadingSubstr.index(after: $0) } ?? leadingSubstr.startIndex
        let sentenceStartOffset = leadingSubstr.distance(
            from: leadingSubstr.startIndex,
            to: sentenceStart
        )

        let trailingStart = upTo
        let trailingRange = NSRange(location: trailingStart,
                                     length: max(0, nsScript.length - trailingStart))
        let trailing = nsScript.substring(with: trailingRange)
        let nextTerminatorOffset = trailing.firstIndex(where: { ".!?".contains($0) })
            .map { trailing.distance(from: trailing.startIndex, to: $0) + 1 }
            ?? trailing.count
        let sentenceEndOffset = trailingStart + nextTerminatorOffset

        let hlStart = script.utf16.index(script.utf16.startIndex, offsetBy: sentenceStartOffset)
        let hlEnd = script.utf16.index(script.utf16.startIndex, offsetBy: min(sentenceEndOffset, script.utf16.count))

        guard let lower = AttributedString.Index(hlStart, within: attr),
              let upper = AttributedString.Index(hlEnd, within: attr),
              lower < upper else {
            _ = terminators
            return attr
        }
        attr[lower..<upper].foregroundColor = Color.primary
        attr[lower..<upper].font = Theme.Typography.body.weight(.semibold)

        // Dim everything else so the spoken sentence reads as the
        // anchor.
        let beforeRange = attr.startIndex..<lower
        attr[beforeRange].foregroundColor = Color.secondary

        let afterRange = upper..<attr.endIndex
        attr[afterRange].foregroundColor = Color(white: 0.4)

        return attr
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
