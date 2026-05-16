import Foundation
import AVFoundation
import SwiftUI

/// Playlist controller for the Read Later queue. Wraps
/// AVSpeechSynthesizer, holds the ordered list of items the user
/// queued for playback, tracks the current index, and auto-advances
/// when an utterance finishes.
///
/// Injected as `@EnvironmentObject` on the root window so the mini
/// player and the playlist screen read the same controller.
@MainActor
final class ReadLaterPlayer: NSObject, ObservableObject {
    enum State {
        case idle
        case playing
        case paused
    }

    /// Queue currently loaded into the player. Persists for the
    /// session — clearing happens when the user explicitly stops
    /// or finishes the last item.
    @Published private(set) var queue: [ReadLaterStory] = []
    /// Index into `queue` of the currently-playing item. nil when
    /// idle or queue is empty.
    @Published private(set) var currentIndex: Int?
    @Published private(set) var state: State = .idle

    /// Cleaned-for-TTS script of the currently-playing item. Updated
    /// on every `startUtterance` call. Used by the now-playing view
    /// to show the spoken text with a highlight on the current
    /// sentence.
    @Published private(set) var currentScript: String = ""
    /// Live progress fraction (0.0...1.0) within `currentScript`,
    /// derived from the synth's `willSpeakRangeOfSpeechString`
    /// callbacks.
    @Published private(set) var currentProgress: Double = 0.0
    /// Char index in `currentScript` where the synth is right now.
    /// Drives the highlighted-sentence calculation in the player UI.
    @Published private(set) var currentSpokenLocation: Int = 0

    /// Playback rate (AVSpeechUtteranceDefaultSpeechRate = 0.5).
    /// User-adjustable from the now-playing sheet.
    @Published var rate: Float = AVSpeechUtteranceDefaultSpeechRate {
        didSet {
            guard oldValue != rate, state != .idle, let i = currentIndex else { return }
            // Restart current utterance at the new rate. AVSpeech
            // doesn't expose a live rate-change; stop + re-speak is
            // the supported path.
            startUtterance(at: i)
        }
    }

    /// Convenience accessor for the now-playing item.
    var currentItem: ReadLaterStory? {
        guard let i = currentIndex, queue.indices.contains(i) else { return nil }
        return queue[i]
    }

    var isActive: Bool {
        state != .idle && currentItem != nil
    }

    /// Closure invoked when an item finishes (used by Phase 6 to
    /// auto-remove from Read Later). Set by the view that owns the
    /// model context.
    var onItemFinished: ((ReadLaterStory) -> Void)?

    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    // MARK: - Queue control

    /// Replace the queue with `items`, start playback from `index`.
    /// Items without a non-empty `playlistScript` are skipped during
    /// playback but still appear in the queue (their UI row stays
    /// visible — the player just advances past them).
    func play(items: [ReadLaterStory], startingAt index: Int = 0) {
        queue = items
        guard !items.isEmpty else {
            stop()
            return
        }
        let clamped = max(0, min(index, items.count - 1))
        activateAudioSession()
        startUtterance(at: clamped)
    }

    /// Toggle play / pause / resume on the current queue item.
    /// If the queue is empty this is a no-op.
    func toggle() {
        guard !queue.isEmpty else { return }
        switch state {
        case .idle:
            startUtterance(at: currentIndex ?? 0)
        case .playing:
            synth.pauseSpeaking(at: .immediate)
        case .paused:
            synth.continueSpeaking()
        }
    }

    func next() {
        guard let i = currentIndex, i + 1 < queue.count else {
            stop()
            return
        }
        startUtterance(at: i + 1)
    }

    func previous() {
        guard let i = currentIndex else { return }
        startUtterance(at: max(0, i - 1))
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        currentIndex = nil
        state = .idle
        deactivateAudioSession()
    }

    // MARK: - Internal

    private func startUtterance(at index: Int) {
        guard queue.indices.contains(index) else {
            stop()
            return
        }
        synth.stopSpeaking(at: .immediate)
        currentIndex = index
        currentProgress = 0
        currentSpokenLocation = 0
        let item = queue[index]
        guard let script = item.playlistScript else {
            currentScript = ""
            if index + 1 < queue.count {
                startUtterance(at: index + 1)
            } else {
                stop()
            }
            return
        }
        let cleaned = SummarySpeechController.stripMarkdown(script)
        guard !cleaned.isEmpty else {
            currentScript = ""
            if index + 1 < queue.count {
                startUtterance(at: index + 1)
            } else {
                stop()
            }
            return
        }
        currentScript = cleaned
        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = AVSpeechSynthesisVoice(
            language: AVSpeechSynthesisVoice.currentLanguageCode()
        )
        utterance.rate = rate
        utterance.preUtteranceDelay = 0.15
        synth.speak(utterance)
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers]
        )
        try? session.setActive(true)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
    }
}

extension ReadLaterPlayer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.state = .playing }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didPause utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.state = .paused }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didContinue utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.state = .playing }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            // Notify the queue owner first so it can pluck the item
            // from Read Later (Phase 6). Snapshot the index before
            // advancing so the callback sees the item that just
            // finished, not the next one.
            if let i = self.currentIndex, self.queue.indices.contains(i) {
                self.onItemFinished?(self.queue[i])
            }
            // Then advance.
            if let i = self.currentIndex, i + 1 < self.queue.count {
                self.startUtterance(at: i + 1)
            } else {
                self.stop()
            }
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        // Cancellation paths handle their own state transitions.
        // Avoid double-firing here.
    }

    /// Fires for every word/range the synth is about to vocalize.
    /// We use the range's location relative to the cleaned script
    /// length to drive the read-only progress bar and the
    /// highlighted-sentence text-follow in NowPlayingView.
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let totalLength = utterance.speechString.count
        let location = characterRange.location
        Task { @MainActor in
            self.currentSpokenLocation = location
            guard totalLength > 0 else {
                self.currentProgress = 0
                return
            }
            self.currentProgress = min(1.0, Double(location + characterRange.length) / Double(totalLength))
        }
    }
}
