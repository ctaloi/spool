import Foundation
import AVFoundation
import MediaPlayer
import SwiftUI

/// Playlist controller for the Spool queue. Wraps
/// AVSpeechSynthesizer, holds the ordered list of items the user
/// queued for playback, tracks the current index, and auto-advances
/// when an utterance finishes.
///
/// Injected as `@EnvironmentObject` on the root window so the mini
/// player and the playlist screen read the same controller.
@MainActor
final class SpoolPlayer: NSObject, ObservableObject {
    enum State {
        case idle
        case playing
        case paused
    }

    /// Queue currently loaded into the player. Persists for the
    /// session — clearing happens when the user explicitly stops
    /// or finishes the last item.
    @Published private(set) var queue: [SpooledStory] = []
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
    /// Length of the range the synth is currently vocalizing —
    /// usually one word, occasionally a punctuation-attached token.
    /// Paired with `currentSpokenLocation` so the UI can render a
    /// word-precise highlight rather than only sentence-level.
    @Published private(set) var currentSpokenLength: Int = 0

    /// Playback rate (AVSpeechUtteranceDefaultSpeechRate = 0.5).
    /// User-adjustable from the now-playing sheet.
    @Published var rate: Float = AVSpeechUtteranceDefaultSpeechRate {
        didSet {
            guard oldValue != rate, state != .idle, let i = currentIndex else { return }
            if let player = audioPlayer, player.isPlaying || state == .paused {
                // Cached-audio path: AVAudioPlayer can change rate
                // live without resampling. No need to restart.
                player.rate = avAudioPlayerRate(for: rate)
            } else {
                // Live-synth path: AVSpeech doesn't expose a live
                // rate change; stop + re-speak is the supported path.
                startUtterance(at: i)
            }
        }
    }

    /// Per-item duration of the currently-loaded cached audio, when
    /// available. Drives the scrubber + lock-screen now-playing
    /// position. Zero while playing via the live synth path.
    @Published private(set) var currentDuration: TimeInterval = 0
    /// Real (wall-clock) seconds into the current cached audio's
    /// playback. Updated by the highlight timer. Zero for synth.
    @Published private(set) var currentTime: TimeInterval = 0

    /// Convenience accessor for the now-playing item.
    var currentItem: SpooledStory? {
        guard let i = currentIndex, queue.indices.contains(i) else { return nil }
        return queue[i]
    }

    var isActive: Bool {
        state != .idle && currentItem != nil
    }

    /// Closure invoked when an item finishes (used by Phase 6 to
    /// auto-remove from Spool). Set by the view that owns the
    /// model context.
    var onItemFinished: ((SpooledStory) -> Void)?

    private let synth = AVSpeechSynthesizer()

    // MARK: - Cached-audio playback path

    /// AVAudioPlayer for pre-rendered TTS. Nil when the active item
    /// is being played by the live synth (cache miss or render
    /// failure).
    private var audioPlayer: AVAudioPlayer?
    /// Timer that polls the audio player's currentTime and advances
    /// the highlighted-range marker. ~10 Hz is enough for a smooth
    /// follow-along without burning the CPU.
    private var highlightTimer: Timer?
    /// Timestamp table for the currently-playing cached audio.
    private var activeTimestamps: [AudioTimestamp] = []
    /// In-flight cache lookup. Cancelled when the user skips so the
    /// previous lookup doesn't suddenly install audio for an item
    /// we've already moved past.
    private var cacheLookupTask: Task<Void, Never>?

    /// Holds the utterance we *most recently* queued with the synth.
    /// The didFinish/didCancel delegates compare incoming events
    /// against this reference and reject anything stale. iOS 17+
    /// has been observed to fire `didFinish` for utterances we
    /// cancelled via `stopSpeaking(.immediate)` — without this
    /// guard, those stale events would trigger an auto-archive of
    /// whatever we just advanced *to*, instead of the one that
    /// finished. ("Skip removed the wrong story.")
    private var currentUtterance: AVSpeechUtterance?

    override init() {
        super.init()
        synth.delegate = self
        setUpRemoteCommands()
    }

    // MARK: - Voice selection

    /// Best-quality voice installed for the user's TTS language.
    /// Premium > Enhanced > Default. Falls back to whatever the system
    /// would have picked anyway if no language-matching voice is found.
    /// Recomputed on each utterance start so a newly-installed voice
    /// is picked up without restarting the app.
    func bestVoice() -> AVSpeechSynthesisVoice? {
        Self.bestVoiceForCurrentLanguage()
    }

    /// Static version of `bestVoice()` so off-main code (the audio
    /// prefetcher, in particular) can pick the same voice the player
    /// will use — keeping the cache key stable.
    nonisolated static func bestVoiceForCurrentLanguage() -> AVSpeechSynthesisVoice? {
        let target = AVSpeechSynthesisVoice.currentLanguageCode()
        let langPrefix = String(target.prefix(2))
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            // Skip novelty voices ("Bad News", "Whisper", etc.) — fine
            // for parlor tricks, wrong for spoken news copy.
            if voice.voiceTraits.contains(.isNoveltyVoice) { return false }
            return voice.language == target || voice.language.hasPrefix(langPrefix)
        }
        let best = candidates.max { a, b in
            qualityRank(a.quality) < qualityRank(b.quality)
        }
        return best ?? AVSpeechSynthesisVoice(language: target)
    }

    /// True iff the voice we'd select right now is Enhanced or
    /// Premium. Drives the one-time onboarding tip in NowPlayingView.
    var hasAdvancedVoice: Bool {
        guard let voice = bestVoice() else { return false }
        return voice.quality == .enhanced || voice.quality == .premium
    }

    nonisolated static func qualityRank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
        switch q {
        case .premium:  return 3
        case .enhanced: return 2
        case .default:  return 1
        @unknown default: return 0
        }
    }

    // MARK: - Queue control

    /// Replace the queue with `items`, start playback from `index`.
    /// Items without a non-empty `playlistScript` are skipped during
    /// playback but still appear in the queue (their UI row stays
    /// visible — the player just advances past them). Auto-advances
    /// through the queue and notifies `onItemFinished` after each
    /// item so the owner can prune it from the spool.
    func play(items: [SpooledStory], startingAt index: Int = 0) {
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
            if let player = audioPlayer {
                player.pause()
                state = .paused
                refreshNowPlayingInfo()
            } else {
                synth.pauseSpeaking(at: .immediate)
            }
        case .paused:
            if let player = audioPlayer {
                player.play()
                state = .playing
                refreshNowPlayingInfo()
            } else {
                synth.continueSpeaking()
            }
        }
    }

    /// Seek the cached-audio player to `seconds` from the start.
    /// No-op if the current item is being played by the live synth
    /// (synth doesn't expose a seek API). Drives the scrubber in
    /// NowPlayingView and the lock-screen seek-bar in Phase 5.
    func seek(to seconds: TimeInterval) {
        guard let player = audioPlayer else { return }
        let clamped = min(max(0, seconds), player.duration)
        player.currentTime = clamped
        updateHighlight()
        // Seek is a transition the now-playing center needs to see,
        // because iOS otherwise interpolates from the pre-seek
        // elapsed time and the lock-screen scrubber visibly snaps
        // back before catching up.
        refreshNowPlayingInfo()
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
        currentUtterance = nil
        stopCachedPlayback()
        cacheLookupTask?.cancel()
        cacheLookupTask = nil
        currentIndex = nil
        currentTime = 0
        currentDuration = 0
        state = .idle
        refreshNowPlayingInfo()
        deactivateAudioSession()
    }

    // MARK: - Internal

    private func startUtterance(at index: Int) {
        guard queue.indices.contains(index) else {
            stop()
            return
        }
        // Tear down any in-flight playback before we move state forward.
        synth.stopSpeaking(at: .immediate)
        currentUtterance = nil
        stopCachedPlayback()
        cacheLookupTask?.cancel()

        currentIndex = index
        currentProgress = 0
        currentSpokenLocation = 0
        currentTime = 0
        currentDuration = 0

        let item = queue[index]
        guard let script = item.playlistScript else {
            currentScript = ""
            advanceOrStop(after: index)
            return
        }
        let cleaned = MarkdownStripper.strip(script)
        guard !cleaned.isEmpty else {
            currentScript = ""
            advanceOrStop(after: index)
            return
        }
        currentScript = cleaned

        // Consult the audio cache first. A hit lets us play the
        // pre-rendered file via AVAudioPlayer (smooth start, no
        // synth wind-up). On miss we fall straight back to live
        // synth so playback isn't blocked while a render happens
        // in the background.
        let voice = bestVoice()
        let key = AudioCacheKey(
            storyID: item.id,
            script: cleaned,
            voice: voice,
            rate: AVSpeechUtteranceDefaultSpeechRate
        )
        let snapshotIndex = index
        cacheLookupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let cached = await AudioCache.shared.lookup(key)
            // The user may have skipped while we were looking up.
            // Bail if the index moved.
            guard !Task.isCancelled, self.currentIndex == snapshotIndex else { return }
            if let cached {
                self.playCached(cached)
            } else {
                self.speakLive(text: cleaned, voice: voice)
            }
        }
    }

    /// Live-synth playback path — the original behavior. Used when
    /// there's no cached render for the current item.
    private func speakLive(text: String, voice: AVSpeechSynthesisVoice?) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        utterance.preUtteranceDelay = 0.15
        currentUtterance = utterance
        synth.speak(utterance)
    }

    /// Cached-audio playback path. Loads the pre-rendered file into
    /// an AVAudioPlayer, applies the user's rate live, and starts a
    /// timer that drives `currentSpokenLocation` from the timestamp
    /// table — same UI affordance as the synth's
    /// `willSpeakRangeOfSpeechString` delegate provides.
    private func playCached(_ cached: CachedAudio) {
        do {
            let player = try AVAudioPlayer(contentsOf: cached.audioURL)
            player.delegate = self
            player.enableRate = true
            player.rate = avAudioPlayerRate(for: rate)
            player.prepareToPlay()
            audioPlayer = player
            activeTimestamps = cached.timestamps
            currentDuration = cached.duration
            state = .playing
            player.play()
            startHighlightTimer()
            refreshNowPlayingInfo()
        } catch {
            // Fall back to live synth if the cached file is corrupt
            // or the audio session can't open it.
            audioPlayer = nil
            activeTimestamps = []
            speakLive(text: currentScript, voice: bestVoice())
        }
    }

    private func startHighlightTimer() {
        highlightTimer?.invalidate()
        // 10 Hz is comfortably smooth for sentence-level highlight
        // tracking and well below CADisplayLink's per-frame budget.
        highlightTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateHighlight() }
        }
    }

    private func stopCachedPlayback() {
        highlightTimer?.invalidate()
        highlightTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        activeTimestamps = []
    }

    private func updateHighlight() {
        guard let player = audioPlayer else { return }
        // The cached file is rendered at the renderer's canonical
        // (synth-default) rate. AVAudioPlayer scales playback to the
        // user's preferred rate, so `currentTime` increases faster
        // than file-time. Convert before binary-searching the
        // timestamp table.
        let rateMultiplier = max(0.1, Double(player.rate))
        let fileTime = player.currentTime * rateMultiplier
        if let ts = activeTimestamps.last(where: { $0.startTime <= fileTime }) {
            currentSpokenLocation = ts.location
            currentSpokenLength = ts.length
        }
        currentTime = player.currentTime
        if player.duration > 0 {
            currentProgress = min(1.0, player.currentTime / player.duration)
        }
        // Note: do NOT push to MPNowPlayingInfoCenter on every tick —
        // iOS interpolates from `elapsedPlaybackTime + playbackRate`,
        // so transition-only pushes (play/pause/seek/track-change)
        // are enough. Repeated pushes at 10 Hz force the now-playing
        // dictionary lock and burn CPU for no visible gain.
    }

    /// Bridges the player's `rate` semantics (default 0.5) to
    /// `AVAudioPlayer.rate` (default 1.0). Clamped to AVAudioPlayer's
    /// supported range of 0.5...2.0.
    private func avAudioPlayerRate(for synthRate: Float) -> Float {
        let normalized = synthRate / AVSpeechUtteranceDefaultSpeechRate
        return min(2.0, max(0.5, normalized))
    }

    /// Move forward in the queue or stop cleanly when there's no
    /// next item. Used by the empty-script skip paths so we share
    /// one termination decision.
    private func advanceOrStop(after index: Int) {
        if index + 1 < queue.count {
            startUtterance(at: index + 1)
        } else {
            stop()
        }
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

    // MARK: - Lock-screen / remote commands

    /// Wires the system remote command center (lock-screen,
    /// Control Center, AirPods, CarPlay) to the same play / pause /
    /// next / previous / seek paths the in-app UI drives. Called
    /// once at init — the command center is process-global so we
    /// don't need to re-register on every play.
    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                if self.state != .playing { self.toggle() }
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                if self.state == .playing { self.toggle() }
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let seekEvent = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            Task { @MainActor in self.seek(to: seekEvent.positionTime) }
            return .success
        }
        // Only enable seek when we have a duration-anchored audio
        // file. Seeking through live-synth utterances isn't
        // meaningful, so disable the command in that case via the
        // periodic now-playing info refresh below.
        center.changePlaybackPositionCommand.isEnabled = false
    }

    /// Push the current item's metadata to the system now-playing
    /// info center. Lock-screen + Control Center read from this. Call
    /// on every state transition and from the highlight timer so the
    /// scrub bar tracks live playback.
    func refreshNowPlayingInfo() {
        guard let item = currentItem else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled = false
            return
        }
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = item.title
        info[MPMediaItemPropertyArtist] = item.author ?? "Hacker News"
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        info[MPNowPlayingInfoPropertyPlaybackRate] = state == .playing ? 1.0 : 0.0
        if currentDuration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = currentDuration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
            MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled = true
        } else {
            // Live-synth path: no real duration, suppress the seek
            // affordance on the lock screen.
            info[MPMediaItemPropertyPlaybackDuration] = 0
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
            MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled = false
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

extension SpoolPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        Task { @MainActor in
            // Reject stale events. If the user (or auto-advance)
            // already moved on, the previous player may still fire
            // its finish callback — applying it now would archive
            // the wrong item.
            guard self.audioPlayer === player else { return }
            self.audioPlayer = nil
            self.highlightTimer?.invalidate()
            self.highlightTimer = nil
            if let i = self.currentIndex, self.queue.indices.contains(i) {
                self.onItemFinished?(self.queue[i])
            }
            if let i = self.currentIndex, i + 1 < self.queue.count {
                self.startUtterance(at: i + 1)
            } else {
                self.stop()
            }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(
        _ player: AVAudioPlayer,
        error: Error?
    ) {
        Task { @MainActor in
            // Cached file went bad — fall back to live synth for
            // this item so playback keeps going.
            guard self.audioPlayer === player else { return }
            self.audioPlayer = nil
            self.highlightTimer?.invalidate()
            self.highlightTimer = nil
            self.speakLive(text: self.currentScript, voice: self.bestVoice())
        }
    }
}

extension SpoolPlayer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.state = .playing
            self.refreshNowPlayingInfo()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didPause utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.state = .paused
            self.refreshNowPlayingInfo()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didContinue utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.state = .playing
            self.refreshNowPlayingInfo()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            // Reject stale events. If the user (or auto-advance)
            // already moved on, iOS may still fire didFinish for the
            // cancelled previous utterance — applying it now would
            // archive the wrong item.
            guard utterance === self.currentUtterance else { return }

            // Notify the queue owner (which moves the row to the
            // Archive), then advance. Snapshot the index before
            // advancing so the callback sees the item that just
            // finished, not the next one.
            if let i = self.currentIndex, self.queue.indices.contains(i) {
                self.onItemFinished?(self.queue[i])
            }
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
        let length = characterRange.length
        Task { @MainActor in
            self.currentSpokenLocation = location
            self.currentSpokenLength = length
            guard totalLength > 0 else {
                self.currentProgress = 0
                return
            }
            self.currentProgress = min(1.0, Double(location + length) / Double(totalLength))
        }
    }
}
