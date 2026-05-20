import Testing
import Foundation
@testable import Spool

/// Sentence powers the highlighted-text scroll in NowPlayingView.
/// Split errors → wrong sentence highlighted. Index lookup errors →
/// stuck scroll. Every transform here is pure.
struct SentenceTests {

    @Test func splitOnPeriods() {
        let sentences = Sentence.split("Hello. World.")
        #expect(sentences.count == 2)
        #expect(sentences[0].text == "Hello.")
        #expect(sentences[1].text == "World.")
    }

    @Test func splitOnQuestionAndExclamation() {
        let sentences = Sentence.split("How? Now. Wow!")
        #expect(sentences.count == 3)
        #expect(sentences.map(\.text) == ["How?", "Now.", "Wow!"])
    }

    @Test func splitPreservesOriginalOffsets() {
        // The synth's willSpeakRange callback uses absolute char
        // offsets into the original script. The Sentence's start/end
        // must therefore match indices into the input string, not
        // into the trimmed text.
        let script = "First. Second. Third."
        let sentences = Sentence.split(script)
        #expect(sentences[0].start == 0)
        #expect(sentences[0].end == 6)         // "First."
        #expect(sentences[1].start == 6)       // after first period
        #expect(sentences[1].end == 14)        // " Second." ends inclusive of period
    }

    @Test func splitOnEmptyStringReturnsEmptyArray() {
        #expect(Sentence.split("") == [])
    }

    @Test func splitHandlesTrailingUnterminatedSentence() {
        // A sentence without `.!?` at the end should still come
        // through — we close it at end-of-string.
        let sentences = Sentence.split("Hello. World")
        #expect(sentences.count == 2)
        #expect(sentences[1].text == "World")
    }

    @Test func splitKeepsNonWhitespaceSegments() {
        // Two consecutive periods produce a lone "." segment between
        // the real ones. The current algorithm keeps it (non-empty
        // after trim) — fine for the highlight use case because the
        // synth blows through it in a millisecond.
        let sentences = Sentence.split("A.. B.")
        #expect(sentences.count == 3)
        #expect(sentences[0].text == "A.")
        #expect(sentences[1].text == ".")
        #expect(sentences[2].text == "B.")
    }

    @Test func splitDropsWhitespaceOnlyRuns() {
        // Pure-whitespace segments (e.g. after a trailing period
        // followed by spaces and nothing else) should not produce
        // an empty row.
        let sentences = Sentence.split("Hello.   ")
        #expect(sentences.count == 1)
        #expect(sentences[0].text == "Hello.")
    }

    @Test func indexContainingMidSentence() {
        let sentences = Sentence.split("First. Second. Third.")
        // Location 8 falls inside "Second.".
        #expect(Sentence.indexContaining(location: 8, in: sentences) == 1)
    }

    @Test func indexContainingAtStart() {
        let sentences = Sentence.split("First. Second.")
        #expect(Sentence.indexContaining(location: 0, in: sentences) == 0)
    }

    @Test func indexContainingPastEndClampsToLast() {
        // The synth's range can momentarily report past the script
        // length during the trailing pause. Clamp to last sentence
        // so we don't render an out-of-range highlight.
        let sentences = Sentence.split("First. Second.")
        #expect(Sentence.indexContaining(location: 9999, in: sentences) == 1)
    }

    @Test func indexContainingOnEmptyListReturnsZero() {
        #expect(Sentence.indexContaining(location: 0, in: []) == 0)
    }
}
