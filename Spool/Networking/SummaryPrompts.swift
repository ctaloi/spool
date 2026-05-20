import Foundation

/// Single source of truth for every system prompt the on-device
/// language model receives. Users can override each prompt from
/// Settings → Prompts; the resolver below prefers the stored
/// override (non-empty) and falls back to the bundled default.
///
/// **Call sites** — `SummaryService` reads `SummaryPrompts.article`,
/// `.comments`, etc. The convenience accessors below resolve the
/// stored override automatically, so the service layer doesn't
/// have to think about customization.
///
/// **Adding a prompt** — drop a default string into `Default`,
/// add a case to `Key`, and add a matching convenience accessor.
/// The Settings UI iterates `Key.allCases` so new prompts appear
/// in the editor automatically.
///
/// **Editing a default** — change the string under `Default` and
/// bump the `defaultVersion` for that key. Users with an old
/// customized prompt get a "Default updated" badge in Settings
/// so they can compare and merge if they care.
enum SummaryPrompts {

    /// Identifier + metadata for each editable prompt.
    enum Key: String, CaseIterable, Identifiable {
        case article
        case comments
        case articleAudio
        case commentsAudio
        case threadQA
        case articleQA

        var id: String { rawValue }

        /// `UserDefaults` key for the user's override text. Empty
        /// string (or unset) = use the bundled default.
        var storageKey: String { "settings.prompt.\(rawValue)" }

        /// `UserDefaults` key for the default-version snapshot the
        /// user's override was forked from. Lets Settings show a
        /// "Default updated" badge when the bundled default has
        /// since changed.
        var forkedFromVersionKey: String { "settings.promptVersion.\(rawValue)" }

        var displayName: String {
            switch self {
            case .article:         return "Article summary"
            case .comments:        return "Comments summary"
            case .articleAudio:    return "Article audio (Spool)"
            case .commentsAudio:   return "Comments audio (Spool)"
            case .threadQA:        return "Thread Q&A"
            case .articleQA:       return "Article Q&A"
            }
        }

        /// One-line context for the Settings row.
        var subtitle: String {
            switch self {
            case .article:
                return "Drives the article half of the summary card."
            case .comments:
                return "Drives the comments half of the summary card."
            case .articleAudio:
                return "Spoken-prose variant played back from the Spool."
            case .commentsAudio:
                return "Spoken-prose variant of the comments summary."
            case .threadQA:
                return "Answers a user-asked question against a comment thread."
            case .articleQA:
                return "Answers a user-asked question against the article."
            }
        }

        /// `basic` prompts surface unconditionally in Settings. Their
        /// output couples loosely with rendering, so casual edits
        /// degrade gracefully. `advanced` prompts (audio, Q&A,
        /// digest) have stricter format contracts — edits to those
        /// land behind a "Show advanced" toggle.
        var tier: Tier {
            switch self {
            case .article, .comments: return .basic
            default: return .advanced
            }
        }

        /// Bump this when the bundled default text changes so users
        /// with a custom override see a "Default updated" nudge.
        /// All defaults start at 1; bump per-key on each change.
        var defaultVersion: Int {
            switch self {
            case .article:         return 1
            case .comments:        return 1
            case .articleAudio:    return 1
            case .commentsAudio:   return 1
            case .threadQA:        return 1
            case .articleQA:       return 1
            }
        }

        var defaultText: String {
            switch self {
            case .article:         return Default.article
            case .comments:        return Default.comments
            case .articleAudio:    return Default.articleAudio
            case .commentsAudio:   return Default.commentsAudio
            case .threadQA:        return Default.threadQA
            case .articleQA:       return Default.articleQA
            }
        }
    }

    enum Tier {
        case basic
        case advanced
    }

    /// Resolves a prompt: stored override if non-empty, otherwise
    /// the bundled default. Reads `UserDefaults` directly so the
    /// service layer picks up edits on the next stream — no
    /// observation / publish ceremony needed for a value used at
    /// request-build time.
    static func resolved(_ key: Key) -> String {
        let stored = UserDefaults.standard.string(forKey: key.storageKey) ?? ""
        return stored.isEmpty ? key.defaultText : stored
    }

    /// True iff the user has stored a non-empty override different
    /// from the current default. Drives the "Customized" chip in
    /// Settings.
    static func isCustomized(_ key: Key) -> Bool {
        let stored = UserDefaults.standard.string(forKey: key.storageKey) ?? ""
        return !stored.isEmpty && stored != key.defaultText
    }

    /// True iff the user customized this prompt against an older
    /// default text version. Drives the "Default updated" nudge.
    /// Returns false when the user hasn't customized at all (no
    /// nudge needed — they'll just keep getting the new default).
    ///
    /// Note: a customization with no stored `forkedFromVersion`
    /// (legacy override predating this code, or someone poking at
    /// UserDefaults directly) reads as `0`, which is strictly less
    /// than every shipped version — so those users see the nudge
    /// and can compare against the current default. That's the
    /// honest call; we can't reconstruct which version they
    /// actually forked from.
    static func defaultHasMovedOn(_ key: Key) -> Bool {
        guard isCustomized(key) else { return false }
        let forkedFrom = UserDefaults.standard.integer(forKey: key.forkedFromVersionKey)
        return forkedFrom < key.defaultVersion
    }

    /// Persists an override + records which default version it was
    /// forked from. Passing an empty string clears the override.
    static func setOverride(_ key: Key, text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty || normalized == key.defaultText.trimmingCharacters(in: .whitespacesAndNewlines) {
            UserDefaults.standard.removeObject(forKey: key.storageKey)
            UserDefaults.standard.removeObject(forKey: key.forkedFromVersionKey)
        } else {
            UserDefaults.standard.set(text, forKey: key.storageKey)
            UserDefaults.standard.set(key.defaultVersion, forKey: key.forkedFromVersionKey)
        }
    }

    // MARK: - Convenience accessors (read by SummaryService)

    static var article: String        { resolved(.article) }
    static var comments: String       { resolved(.comments) }
    static var articleAudio: String   { resolved(.articleAudio) }
    static var commentsAudio: String  { resolved(.commentsAudio) }
    static var threadQA: String       { resolved(.threadQA) }
    static var articleQA: String      { resolved(.articleQA) }

    // MARK: - Defaults
    //
    // Bundled prompt text. Edit a string here AND bump the matching
    // `defaultVersion` in `Key.defaultVersion` to flag the change to
    // users who customized an earlier version.

    enum Default {
        static let article = """
        You summarize news articles for a Hacker News reader. Use only facts from the article text below — never invent.

        If the text is too short, paywalled, or missing, output exactly: Not enough article content to summarize

        Otherwise, output in this exact format:

        [One sentence stating the article's main claim. No label, no prefix.]

        - [Most important fact]
        - [Second fact]
        - [Third fact]
        - [Optional fourth]
        - [Optional fifth]

        **Why HN cares:** [One paragraph, 1–2 sentences, on the specific technical or industry angle. Be concrete — name the tradeoff, the unexpected detail, or the second-order effect. Avoid generic phrases like "raises questions about" or "has implications for".]

        Do not repeat the title. Do not speculate. Neutral tone.
        """

        static let comments = """
        You summarize a Hacker News comment thread. Use only the comments provided. Never invent comments, quotes, or usernames. Paraphrase only — no direct quotes. Do not include usernames.

        If the thread is too short or low-signal, output exactly: Not enough discussion to summarize

        Otherwise, output in this exact format:

        **Sentiment**: [One short line. Examples: Mostly skeptical. Strong agreement. Split between two camps. Off-topic tangent.]

        **Themes**
        - [One sentence on the most engaged-with discussion]
        - [One sentence on the next]
        - [3–5 bullets total, plain prose, no bold prefixes]

        **Notable disagreements**
        - [One sentence on a specific point people disagree on]
        - [Optional second]

        (Omit the Notable disagreements section entirely if the thread is broadly in agreement.)

        **Sharp take**: [One sentence paraphrasing the single most non-obvious comment.]

        **Worth reading if**: [One short line on who'd get value from clicking through.]

        The only bold labels are the section names above. Do not bold anything else.
        """

        static let articleAudio = """
        You summarize a news article to be read aloud by a text-to-speech engine. The listener is on a walk, in the car, or cooking.

        If the article text is too short, paywalled, or missing, output exactly: Not enough article content to summarize

        Otherwise, write 3 to 5 short paragraphs of plain prose. Each paragraph is one or two sentences. Target 90 to 150 words total — roughly 45 seconds of audio.

        Paragraph 1: The main claim, stated naturally. No label like "TL;DR".
        Paragraphs 2–3 (or 4): The most important supporting facts.
        Final paragraph: One sentence on why this matters to a technical audience. Phrase it as a natural thought, not a section header.

        Use connective phrases between paragraphs so it flows — "Beyond that," "The reason this matters is," "On the technical side,".

        Rules:
        - No markdown. No bullets. No headings. No asterisks. No section labels.
        - Do not repeat the title.
        - Spell out symbols and versions for speech: say "version 3" not "v3", "macOS Sequoia" not "macOS 15".
        - Expand acronyms on first use if they're not household names. "LLM" and "API" are fine as-is. "RAG" or "MCP" — spell out the first time.
        - Neutral tone. No speculation.
        """

        static let commentsAudio = """
        You summarize a Hacker News comment thread to be read aloud by a text-to-speech engine.

        If the thread is too short or low-signal, output exactly: Not enough discussion to summarize

        Otherwise, write 2 to 4 short paragraphs of plain prose. Each paragraph is one or two sentences. Target 70 to 130 words total — roughly 40 seconds of audio.

        Paragraph 1: The overall tone of the discussion, phrased naturally. Example: "The thread is mostly skeptical of the central claim, with several commenters pushing back on the methodology." Not: "Sentiment: skeptical."
        Paragraphs 2–3: The main discussion threads, described in flowing prose.
        Final paragraph (optional): The single sharpest or most non-obvious take, woven in naturally.

        Use connective phrases — "A separate thread debates," "One commenter makes the point that," "On the other hand,".

        Rules:
        - No markdown. No bullets. No headings. No section labels.
        - Paraphrase only — no direct quotes.
        - Never include usernames.
        - Neutral tone.
        """

        static let threadQA = """
        You answer a reader's question about a Hacker News thread, using only the comments provided.

        If the thread doesn't address the question, output exactly: The thread doesn't really cover this

        If the question asks for your opinion or predictions, answer based only on what the comments say — do not add your own view.

        Otherwise, output in this format:

        [One short paragraph, 2–4 sentences, answering directly.]

        - [Strongest supporting point from the thread]
        - [Counter-argument or caveat]
        - [Optional third or fourth]

        Paraphrase only. No direct quotes. No usernames. Neutral tone.
        """

        static let articleQA = """
        You answer a reader's question about a news article, using only the article text.

        If the article doesn't address the question, output exactly: The article doesn't cover this

        If the question asks for opinion or prediction, answer only with what the article states — do not speculate.

        Otherwise, output in this format:

        [One short paragraph answering directly.]

        - [Supporting specific from the text]
        - [Optional second]
        - [Optional third]

        Use only facts from the article. No speculation.
        """
    }
}
