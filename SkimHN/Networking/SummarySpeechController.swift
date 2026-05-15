import AVFoundation
import SwiftUI

/// Wraps AVSpeechSynthesizer for reading a summary aloud. On-device,
/// no network, no Apple Intelligence dependency — TTS ships with
/// every iOS install.
///
/// The controller is a `@StateObject` on whichever card owns the
/// summary; toggling cycles idle → speaking → paused. Calling
/// `stop()` on view disappear keeps audio from outlasting the
/// detail page when the user swipes away.
@MainActor
final class SummarySpeechController: NSObject, ObservableObject {
    enum State {
        case idle
        case speaking
        case paused
    }

    @Published private(set) var state: State = .idle

    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    /// One-button entry point: tap to start, tap again to pause,
    /// tap once more to resume. Mirrors how the system Media controls
    /// behave so the gesture is familiar.
    func toggle(text: String) {
        switch state {
        case .idle:
            speak(text)
        case .speaking:
            synth.pauseSpeaking(at: .immediate)
        case .paused:
            synth.continueSpeaking()
        }
    }

    /// Hard stop. Cancels the current utterance immediately and
    /// flips state back to .idle. Safe to call from `.onDisappear`.
    func stop() {
        guard state != .idle else { return }
        synth.stopSpeaking(at: .immediate)
        state = .idle
    }

    private func speak(_ markdown: String) {
        let cleaned = Self.stripMarkdown(markdown)
        guard !cleaned.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = AVSpeechSynthesisVoice(
            language: AVSpeechSynthesisVoice.currentLanguageCode()
        )
        // Stock default rate — slightly under "fast" so headers and
        // bullets read naturally. We don't expose a settings slider;
        // the user can pinch in iOS Accessibility settings.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.preUtteranceDelay = 0.1
        synth.speak(utterance)
    }

    /// Convert summary Markdown to TTS-friendly prose.
    /// - Bullets / headings become sentences (period at end → natural pause).
    /// - Inline emphasis (`**bold**`, `*italic*`, `_under_`, `` `code` ``)
    ///   has its markers stripped so the synth doesn't read them aloud.
    /// - Empty lines are dropped; everything joins into one paragraph
    ///   with sentence-period separators.
    static func stripMarkdown(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        let cleaned: [String] = lines.compactMap { raw in
            var s = raw.trimmingCharacters(in: .whitespaces)

            // Drop leading bullet markers — the bullet line becomes a sentence.
            for marker in ["- ", "* ", "+ ", "• ", "· ", "‣ "] where s.hasPrefix(marker) {
                s = String(s.dropFirst(marker.count))
                break
            }

            // Drop leading heading markers.
            while s.hasPrefix("#") {
                s = String(s.dropFirst())
            }
            s = s.trimmingCharacters(in: .whitespaces)

            // Inline emphasis markers — replace bold/italic/code marks.
            // Order matters: ** before * so we don't half-eat **bold**.
            s = s.replacingOccurrences(of: "**", with: "")
            s = s.replacingOccurrences(of: "__", with: "")
            s = s.replacingOccurrences(of: "*", with: "")
            s = s.replacingOccurrences(of: "_", with: "")
            s = s.replacingOccurrences(of: "`", with: "")

            // Numbered list prefix (`1.`, `2.` …) — strip the number,
            // keep the body.
            if let match = s.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                s = String(s[match.upperBound...])
            }

            if s.isEmpty { return nil }

            // Ensure each line ends with a sentence-terminating mark
            // so the synth pauses between bullets / paragraphs.
            if let last = s.last, !".!?:,;".contains(last) {
                s += "."
            }
            return s
        }
        return cleaned.joined(separator: " ")
    }
}

extension SummarySpeechController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.state = .speaking }
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
        Task { @MainActor in self.state = .speaking }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.state = .idle }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.state = .idle }
    }
}
