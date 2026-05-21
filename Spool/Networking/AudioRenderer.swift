import AVFoundation
import Foundation
import os.log

private let audioRendererLog = Logger(subsystem: "news.getspool.app", category: "AudioRenderer")

/// One timed range in the rendered audio. `location`/`length` index
/// into the input text; `startTime` is the moment that range begins
/// in the audio file (seconds, 0-anchored).
struct AudioTimestamp: Codable, Hashable {
    let location: Int
    let length: Int
    let startTime: TimeInterval

    var nsRange: NSRange { NSRange(location: location, length: length) }
}

/// Result of an offline TTS render. The audio file lives at `audioURL`;
/// `timestamps` is the per-word/range table the player uses to sync
/// the highlighted sentence and to scrub.
struct AudioRenderResult {
    let audioURL: URL
    let duration: TimeInterval
    let timestamps: [AudioTimestamp]
}

enum AudioRenderError: Error, LocalizedError {
    case unsupportedBufferFormat
    case fileWriteFailed(Error)
    case noAudioProduced
    case timedOut
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unsupportedBufferFormat: return "Speech synth produced an unexpected buffer format."
        case .fileWriteFailed(let e): return "Audio file write failed: \(e.localizedDescription)"
        case .noAudioProduced: return "Speech synth produced no audio."
        case .timedOut: return "Speech synth render exceeded its time budget."
        case .cancelled: return "Speech synth render was cancelled."
        }
    }
}

/// Renders an utterance to an audio file offline (without playing it
/// through the speaker) and captures the timing of each spoken range
/// so the player can sync a sentence-by-sentence highlight to the
/// pre-rendered audio.
///
/// Built on `AVSpeechSynthesizer.write(_:toBufferCallback:)`. The
/// buffer callback writes PCM frames to the output file and tracks
/// the running frame count; the `willSpeakRangeOfSpeechString`
/// delegate event records (characterRange, current-seconds) pairs
/// using `frameCount / sampleRate` as the time anchor.
///
/// Designed to be invoked from the prefetcher in the background. One
/// renderer can be reused across multiple sequential renders; do not
/// share across concurrent calls.
final class AudioRenderer: @unchecked Sendable {
    /// Active rendering session. Held strongly while the synth is
    /// writing so the delegate doesn't get torn down mid-render.
    /// Mutated only from `render(...)` calls — the renderer is meant
    /// to be used sequentially, one render at a time. Shared safely
    /// across threads only as far as that contract is honored.
    private var activeSession: RenderSession?

    init() {}

    /// Render `text` to a CAF file at `outputURL`. Resolves on the
    /// main actor when the synth finishes producing audio.
    func render(
        text: String,
        voice: AVSpeechSynthesisVoice?,
        rate: Float,
        to outputURL: URL
    ) async throws -> AudioRenderResult {
        let session = RenderSession(
            text: text,
            voice: voice,
            rate: rate,
            outputURL: outputURL
        )
        activeSession = session
        defer { activeSession = nil }
        return try await session.run()
    }
}

/// Single-shot rendering session. Bundles the synth, its delegate
/// hooks, and the in-flight audio file so a renderer can keep its
/// state cleanly separated from any future renders.
///
/// `@unchecked Sendable` because the synth's buffer/delegate
/// callbacks fire on a private queue while the renderer is awaiting
/// a continuation — but all mutations target properties only this
/// session reads, and the AudioRenderer holds at most one session
/// at a time, so there's no actual sharing across actors.
private final class RenderSession: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let text: String
    private let voice: AVSpeechSynthesisVoice?
    private let rate: Float
    private let outputURL: URL

    private let synth = AVSpeechSynthesizer()
    private var audioFile: AVAudioFile?
    private var totalFrames: AVAudioFramePosition = 0
    private var sampleRate: Double = 0
    private var timestamps: [AudioTimestamp] = []
    private var continuation: CheckedContinuation<AudioRenderResult, Error>?
    private var didComplete = false
    /// Watchdog timer. If the synth never produces an end-of-stream
    /// buffer (rare but possible on some voices when the process is
    /// backgrounded mid-write), the continuation would otherwise hang
    /// forever and leak the awaiting Task.
    private var watchdog: DispatchSourceTimer?

    init(text: String, voice: AVSpeechSynthesisVoice?, rate: Float, outputURL: URL) {
        self.text = text
        self.voice = voice
        self.rate = rate
        self.outputURL = outputURL
        super.init()
        synth.delegate = self
    }

    func run() async throws -> AudioRenderResult {
        try await withCheckedThrowingContinuation { [self] cont in
            self.continuation = cont

            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            utterance.rate = rate
            // No pre/post delay — the player adds gaps between items
            // explicitly. Tight bookends keep scrubbing accurate.
            utterance.preUtteranceDelay = 0
            utterance.postUtteranceDelay = 0

            // Watchdog: 120 s is comfortably above the worst observed
            // synth render time for a 5-min summary. If we hit it,
            // assume the synth wedged and fail the continuation so
            // the caller's Task can unwind cleanly.
            startWatchdog(seconds: 120)

            synth.write(utterance) { [weak self] buffer in
                self?.handle(buffer: buffer)
            }
        }
    }

    deinit {
        // Last-line defense against a leaked continuation. If the
        // session is being torn down with the synth still in flight
        // (process backgrounded, owner deallocated), surface the
        // cancellation so the awaiting Task doesn't hang forever.
        watchdog?.cancel()
        if !didComplete, let cont = continuation {
            cont.resume(throwing: AudioRenderError.cancelled)
        }
    }

    private func startWatchdog(seconds: TimeInterval) {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + seconds, repeating: .never)
        timer.setEventHandler { [weak self] in
            self?.fail(.timedOut)
        }
        timer.resume()
        watchdog = timer
    }

    // MARK: - Buffer pipeline

    private func handle(buffer: AVAudioBuffer) {
        // The buffer callback fires on a private serial queue. We
        // can write to AVAudioFile from here safely as long as we
        // don't bounce back to the main actor mid-write.
        guard let pcm = buffer as? AVAudioPCMBuffer else {
            fail(.unsupportedBufferFormat)
            return
        }

        // Lazily open the output file once we know the synth's
        // chosen format. Different voices can produce different
        // sample rates; matching the synth keeps the write
        // bit-perfect.
        if audioFile == nil {
            do {
                let format = pcm.format
                sampleRate = format.sampleRate
                audioFile = try AVAudioFile(
                    forWriting: outputURL,
                    settings: format.settings,
                    commonFormat: format.commonFormat,
                    interleaved: format.isInterleaved
                )
            } catch {
                fail(.fileWriteFailed(error))
                return
            }
        }

        // The synth signals end-of-stream by sending an empty buffer.
        if pcm.frameLength == 0 {
            finish()
            return
        }

        do {
            try audioFile?.write(from: pcm)
            totalFrames += AVAudioFramePosition(pcm.frameLength)
        } catch {
            fail(.fileWriteFailed(error))
        }
    }

    private func finish() {
        guard !didComplete else { return }
        didComplete = true
        watchdog?.cancel()
        watchdog = nil
        guard sampleRate > 0, totalFrames > 0 else {
            continuation?.resume(throwing: AudioRenderError.noAudioProduced)
            continuation = nil
            return
        }
        // Close the file before we hand the URL back.
        audioFile = nil
        let duration = TimeInterval(totalFrames) / sampleRate
        let result = AudioRenderResult(
            audioURL: outputURL,
            duration: duration,
            timestamps: timestamps
        )
        audioRendererLog.debug("Rendered \(self.text.count, privacy: .public)ch → \(duration, privacy: .public)s (\(self.timestamps.count, privacy: .public) timestamps)")
        continuation?.resume(returning: result)
        continuation = nil
    }

    private func fail(_ error: AudioRenderError) {
        guard !didComplete else { return }
        didComplete = true
        watchdog?.cancel()
        watchdog = nil
        audioFile = nil
        continuation?.resume(throwing: error)
        continuation = nil
    }

    // MARK: - AVSpeechSynthesizerDelegate

    /// Fires for each upcoming spoken range during the offline render.
    /// We anchor it to the frames written so far — once we know the
    /// sample rate from the first buffer, `frames / sampleRate` is
    /// the timestamp where this range will start in the file.
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        // The delegate may fire from the synth's worker queue. The
        // session's frame counters are mutated on the same buffer
        // queue, so a brief race on `totalFrames`/`sampleRate` is
        // possible — but the error is bounded by one buffer's
        // duration (~20-40ms), which the player can tolerate. If
        // this proves audible in practice, swap in a serial-queue
        // sync around buffer-write + timestamp capture.
        let seconds = sampleRate > 0
            ? Double(totalFrames) / sampleRate
            : 0
        timestamps.append(AudioTimestamp(
            location: characterRange.location,
            length: characterRange.length,
            startTime: seconds
        ))
    }
}
