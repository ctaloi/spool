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
        let item = queue[index]
        guard let script = item.playlistScript else {
            // Nothing to read — jump to the next item.
            if index + 1 < queue.count {
                startUtterance(at: index + 1)
            } else {
                stop()
            }
            return
        }
        let cleaned = SummarySpeechController.stripMarkdown(script)
        guard !cleaned.isEmpty else {
            if index + 1 < queue.count {
                startUtterance(at: index + 1)
            } else {
                stop()
            }
            return
        }
        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = AVSpeechSynthesisVoice(
            language: AVSpeechSynthesisVoice.currentLanguageCode()
        )
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
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
}
