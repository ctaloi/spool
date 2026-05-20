import Foundation

/// One sentence-shaped chunk of a spoken script with character-range
/// anchors into the original. Used by `NowPlayingView` to render the
/// script as separate `Text` rows (so `ScrollViewReader.scrollTo`
/// actually navigates) and to map the synthesizer's
/// `willSpeakRangeOfSpeechString` callback to the highlighted row.
///
/// Extracted from `NowPlayingView` so the splitting / lookup logic is
/// testable without standing up a full SwiftUI view.
struct Sentence: Equatable {
    let text: String
    let start: Int
    let end: Int

    /// Walk the script char-by-char, cutting on sentence- and
    /// clause-level boundaries so AI prose without strong punctuation
    /// still breaks into reasonably-sized chunks (instead of one
    /// paragraph-shaped block). Breaks fire on:
    ///   - `.!?` — true sentence terminators
    ///   - `;`   — clause terminator the synth treats as a long pause
    ///   - `\n`  — newlines from markdown-ish output
    ///   - end of string
    ///
    /// `:` is intentionally NOT a break — section headings ("Why HN
    /// cares: ...") read better as a single chunk.
    ///
    /// Also enforces a soft chunk cap (~240 chars). If we walk that
    /// far without hitting a boundary, we cut at the next space so a
    /// 1,500-char monologue still ends up scrollable.
    /// Whitespace at the head of each sentence is trimmed for display
    /// but the original offsets are preserved so we can match the
    /// speech location.
    static func split(_ script: String) -> [Sentence] {
        guard !script.isEmpty else { return [] }
        var result: [Sentence] = []
        let chars = Array(script)
        var segmentStart = 0
        for (i, char) in chars.enumerated() {
            let atEnd = i == chars.count - 1
            let runLen = (i + 1) - segmentStart
            let hardBreak = ".!?;\n".contains(char)
            // Soft cap: if the chunk has run long without a hard
            // break, cut at the next whitespace.
            let softBreak = runLen >= 240 && char.isWhitespace
            if hardBreak || softBreak || atEnd {
                let endExclusive = i + 1
                let raw = String(chars[segmentStart..<endExclusive])
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    // Shift `start` past any leading whitespace so it
                    // points at the first character of the *trimmed*
                    // text. Without this, mapping a script-space
                    // highlight range onto the trimmed text drops
                    // the first letter of every word that follows a
                    // sentence break (the leading space gets counted
                    // as part of the sentence text).
                    let leadingWS = raw.prefix(while: { $0.isWhitespace || $0.isNewline }).count
                    result.append(Sentence(
                        text: trimmed,
                        start: segmentStart + leadingWS,
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
