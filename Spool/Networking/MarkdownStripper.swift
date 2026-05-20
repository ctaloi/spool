import Foundation

/// Converts the AI-generated summary Markdown into TTS-ready prose
/// for `SpoolPlayer`'s utterances. Bullets, headings, and inline
/// emphasis markers become readable sentences with natural pauses.
///
/// Extracted from the now-deleted per-summary-card "read aloud"
/// controller — the only remaining use of this transform is the
/// Spool playlist's audio script. A static enum keeps it light
/// (no instance state, no actor isolation) so callers don't have
/// to think about scope.
enum MarkdownStripper {

    /// Convert summary Markdown to TTS-friendly prose.
    /// - Bullets / headings become sentences (period at end → natural pause).
    /// - Inline emphasis (`**bold**`, `*italic*`, `_under_`, `` `code` ``)
    ///   has its markers stripped so the synth doesn't read them aloud.
    /// - Empty lines are dropped; everything joins into one paragraph
    ///   with sentence-period separators.
    static func strip(_ markdown: String) -> String {
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
