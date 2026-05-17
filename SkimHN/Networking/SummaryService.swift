import Foundation
import FoundationModels

enum SummaryAvailability: Equatable {
    case available
    case appleIntelligenceDisabled
    case modelNotReady
    case unsupportedDevice
    case other(String)

    var userMessage: String {
        switch self {
        case .available:
            return "Apple Intelligence ready"
        case .appleIntelligenceDisabled:
            return "Enable Apple Intelligence in Settings to summarize articles"
        case .modelNotReady:
            return "Apple Intelligence is still downloading — try again shortly"
        case .unsupportedDevice:
            return "On-device summaries aren't supported on this device"
        case .other(let s):
            return s
        }
    }
}

@MainActor
final class SummaryService {
    static let shared = SummaryService()

    private init() {}

    var availability: SummaryAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceDisabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable(.deviceNotEligible):
            return .unsupportedDevice
        case .unavailable(let reason):
            return .other(String(describing: reason))
        }
    }

    /// Convenience for the many gate-on-AI render checks across the
    /// app. True only when the model can actually serve a request
    /// right now — covers any future `unavailable` reason without
    /// pattern-match drift at each call site.
    var isAvailable: Bool {
        availability == .available
    }

    /// Streams a summary; each yielded String is the cumulative response so far.
    func summarize(
        title: String,
        articleText: String
    ) -> AsyncThrowingStream<String, Error> {
        makeAppleStream(
            instructions: Self.articleInstructions,
            prompt: "Title: \(title)\n\nArticle text:\n\(articleText)"
        )
    }

    /// Streams a digest of the comments thread.
    func summarizeComments(
        title: String,
        comments: String
    ) -> AsyncThrowingStream<String, Error> {
        makeAppleStream(
            instructions: Self.commentsInstructions,
            prompt: "Story: \(title)\n\nComments thread (oldest top-level first; indentation shows replies):\n\(comments)"
        )
    }

    /// Streams an answer to a user-asked question about the comment
    /// thread. Stays grounded in the provided transcript.
    func answerThreadQuestion(
        title: String,
        comments: String,
        question: String
    ) -> AsyncThrowingStream<String, Error> {
        let prompt = """
        Story: \(title)

        Comments thread (oldest top-level first; indentation shows replies):
        \(comments)

        Question: \(question)
        """
        return makeAppleStream(
            instructions: Self.threadQAInstructions,
            prompt: prompt
        )
    }

    /// Streams an answer to a user-asked question about the article
    /// text. Same Q&A pattern as the comment thread, different scope.
    func answerArticleQuestion(
        title: String,
        articleText: String,
        question: String
    ) -> AsyncThrowingStream<String, Error> {
        let prompt = """
        Title: \(title)

        Article text:
        \(articleText)

        Question: \(question)
        """
        return makeAppleStream(
            instructions: Self.articleQAInstructions,
            prompt: prompt
        )
    }

    /// Audio-tuned article summary for the Read Later playlist. The
    /// model is told this is being read aloud, so the output is
    /// conversational prose with no markdown / bullets / labels.
    /// Section transitions become full sentences.
    func summarizeArticleForAudio(
        title: String,
        articleText: String
    ) -> AsyncThrowingStream<String, Error> {
        makeAppleStream(
            instructions: Self.articleAudioInstructions,
            prompt: "Title: \(title)\n\nArticle text:\n\(articleText)"
        )
    }

    /// Audio-tuned comments summary for the Read Later playlist.
    /// Same conversational pivot — no markdown headings ("Sentiment",
    /// "Themes") that sound clinical when spoken.
    func summarizeCommentsForAudio(
        title: String,
        comments: String
    ) -> AsyncThrowingStream<String, Error> {
        makeAppleStream(
            instructions: Self.commentsAudioInstructions,
            prompt: "Story: \(title)\n\nComments thread (oldest top-level first; indentation shows replies):\n\(comments)"
        )
    }

    /// Streams a "what you missed since you last opened the app"
    /// digest given a list of recent top stories.
    func digestRecentStories(
        headlines: String
    ) -> AsyncThrowingStream<String, Error> {
        makeAppleStream(
            instructions: Self.digestInstructions,
            prompt: "Recent top stories:\n\(headlines)"
        )
    }

    private static let articleInstructions = """
    You are a concise news-article summarizer for a Hacker News reader. \
    Produce a tight summary of the article the user provides.

    Format:
    - Open with one short sentence in plain prose summarizing the key claim. \
      Do NOT prefix it with "TL;DR", "Summary:", or any other label — the \
      surrounding UI already says this is a summary.
    - Follow with 3 to 5 bullet points covering the most important facts, in \
      order of importance. Use short, declarative bullets.
    - End with one paragraph prefixed exactly with "**Why HN cares:**" \
      explaining the angle that makes this interesting to a technical audience.

    Rules:
    - Use only facts present in the provided text. If the text is too short, \
    paywalled, or missing, say "Not enough article content to summarize" and stop.
    - Do not repeat the title.
    - Do not speculate, editorialize, or predict reactions.
    - Neutral tone, no links.
    """

    private static let commentsInstructions = """
    You summarize Hacker News comment threads to help a reader decide whether to dive in.

    Format the response in Markdown EXACTLY like this:

    **Sentiment**: one short line on overall tone (e.g., "Mostly skeptical", "Strong consensus", "Split", "Off-topic tangent").

    **Themes**
    - 3 to 5 short bullets, each capturing one distinct discussion thread in a single sentence.
    - Lead with the thread that has the most replies.
    - Each bullet is plain prose — do NOT prefix individual bullets with a bold label or topic title.

    **Notable disagreements**
    - 1 to 2 short bullets on specific points of meaningful disagreement.
    - Each bullet is plain prose with no bold label prefix.
    - Omit this entire section if the thread is broadly consensus.

    **Sharp take**: one sentence paraphrasing the single most interesting or non-obvious comment.

    **Worth reading if**: one short line on who would get value from clicking through.

    Rules:
    - Use only content from the provided comments. Do not invent comments or quotes.
    - Do not include usernames, even if they appear in the text.
    - Paraphrase only — no direct quotes.
    - Neutral tone. Concrete claims over generalities.
    - The only bold labels in the response are the section names listed above. Do not bold-label anything else.
    - If the thread is too short or low-signal, say "Not enough discussion to summarize" and stop.
    """

    private static let threadQAInstructions = """
    You answer a reader's question about a Hacker News comment thread, using ONLY the comments provided.

    Format:
    - Open with one short paragraph answering the question directly. If the thread doesn't address it, say so plainly — don't invent.
    - Then 2–4 bullets surfacing the strongest supporting points or counter-arguments from the thread.

    Rules:
    - Ground every claim in the provided comments.
    - Paraphrase — no direct quotes.
    - No usernames.
    - If the thread is silent on the question, say "The thread doesn't really cover this" and stop.
    - Neutral tone, concrete claims, no editorializing.
    """

    /// Audio-friendly variant for the Read Later playlist. The
    /// in-app summary is laid out with markdown headings and
    /// bullets for visual scanning; spoken aloud, those structural
    /// markers read clinically ("Bullet one. Bullet two."). The
    /// audio prompt asks for flowing conversational prose — the
    /// kind of brief explainer a knowledgeable friend would
    /// volunteer over coffee.
    private static let articleAudioInstructions = """
    You are summarizing a Hacker News article for a listener who is hearing \
    this read aloud — over AirPods on a walk, in the car, while cooking. The \
    output goes straight to a text-to-speech engine.

    Style:
    - Plain conversational prose. No markdown, no bullets, no headings, no \
      asterisks, no labels like "TL;DR" or "Why HN cares".
    - 3 to 5 short paragraphs, each one or two sentences. Aim for the cadence \
      a friend would use explaining the piece in passing.
    - Lead with the one-sentence gist. Then the most important supporting \
      facts. Close with one sentence on why this is interesting to a \
      technically literate audience — phrased naturally, not as a section.
    - Use simple connective phrases between paragraphs ("Beyond that,", \
      "The reason this matters is", "On the technical side,") so the audio \
      flows rather than jumping.
    - Target 90 to 150 spoken words total — roughly 45 seconds of audio.

    Rules:
    - Only use facts present in the provided article text. If the text is too \
      short, paywalled, or missing, say "Not enough article content to summarize" \
      and stop.
    - Do not repeat the title.
    - No speculation, no editorializing, no predictions about reactions.
    - Neutral tone. Avoid acronyms unless they appear in the source.
    - Spell out symbols when ambiguous in speech (say "version 3" not "v3").
    """

    /// Audio-friendly variant for the comments side of the Read
    /// Later playlist. Same conversational pivot — section labels
    /// ("Sentiment:", "Themes:") become natural prose connectors so
    /// the digest sounds like reportage, not a checklist.
    private static let commentsAudioInstructions = """
    You are summarizing a Hacker News comment thread for a listener who is \
    hearing this read aloud. The output goes straight to a text-to-speech \
    engine.

    Style:
    - Plain conversational prose. No markdown, no bullets, no headings, no \
      asterisks, no section labels like "Sentiment:" or "Themes:".
    - 2 to 4 short paragraphs, each one or two sentences.
    - Open with a natural-sounding take on the overall tone of the discussion \
      ("The thread is mostly skeptical of the claim that …" rather than \
      "Sentiment: skeptical"). Then describe the main discussion threads in \
      flowing prose. If there's a single sharp take worth surfacing, weave \
      it in as a final paragraph.
    - Use connective phrases ("A separate thread debates", "One commenter \
      makes the point that", "On the other hand,") so the audio doesn't \
      jump between topics.
    - Target 70 to 130 spoken words total — roughly 40 seconds of audio.

    Rules:
    - Only use content from the provided comments. Do not invent comments or \
      quotes.
    - Do not include usernames, even if they appear in the text.
    - Paraphrase only — no direct quotes.
    - Neutral tone. Concrete claims over generalities.
    - If the thread is too short or low-signal, say "Not enough discussion \
      to summarize" and stop.
    """

    private static let articleQAInstructions = """
    You answer a reader's question about a news article, using ONLY the article text provided.

    Format:
    - One short paragraph answering directly. If the article doesn't address it, say so.
    - 1–3 bullets with supporting specifics from the text.

    Rules:
    - Use only facts present in the article.
    - No speculation.
    - No editorializing.
    """

    private static let digestInstructions = """
    You write a brief "what you missed" catch-up for a Hacker News reader who hasn't opened the app in a while.

    Format:
    - One opening line setting the TOPICAL scene — what's the overall flavor of today's stories? Examples: "Heavy on AI.", "Mostly infra and developer-tool news.", "A quiet batch — a few hardware launches and one paywall debate.", "Mixed bag with AI, healthcare, and policy."
    - 3–5 bullets, each grouping related stories under a short theme. Lead with the most-discussed/highest-score themes.
    - No links, no usernames, no scores.

    Rules:
    - Use only the provided story titles. Don't fabricate stories.
    - Do NOT reference time of day — never say "morning", "afternoon", "evening", "tonight", or any time-based framing. You don't know when the user is reading this.
    - Keep it under 90 words total.
    - Conversational, lightly punchy. Not corporate.
    """

    private func makeAppleStream(
        instructions: String,
        prompt: String
    ) -> AsyncThrowingStream<String, Error> {
        let session = LanguageModelSession(instructions: instructions)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream = session.streamResponse(to: prompt)
                    for try await partial in stream {
                        // `partial` is FoundationModels' Snapshot wrapper —
                        // pull `.content` so we stream the generated text,
                        // not the type's debug description.
                        continuation.yield(partial.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: SummaryError.classify(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

enum SummaryError: LocalizedError {
    case emptyArticle
    /// Apple's on-device model declined to process the prompt or its own
    /// output. There is no documented way to bypass this — we surface a
    /// clear message and let the user open the article directly.
    case guardrail
    /// The prompt exceeded the model's context window even after shrinking
    /// to the minimum article budget.
    case contextTooLong
    /// Anything else — passes through the original message.
    case other(String)

    var errorDescription: String? {
        switch self {
        case .emptyArticle:
            return "Couldn't extract any text from the article."
        case .guardrail:
            return "The on-device model declined to summarize this content."
        case .contextTooLong:
            return "This is too long to summarize on-device."
        case .other(let message):
            return message
        }
    }

    /// Pattern-match the error's type name, debug description, and
    /// localized message. We avoid switching on `LanguageModelSession.GenerationError`
    /// cases directly because their names have shifted between SDK betas;
    /// keyword matching across all three text sources stays stable.
    static func classify(_ error: Error) -> SummaryError {
        if let already = error as? SummaryError { return already }

        let typeName = String(reflecting: type(of: error))
        let debug = String(describing: error)
        let localized = error.localizedDescription
        let blob = "\(typeName) \(debug) \(localized)".lowercased()

        let guardrailHits = ["guardrail", "refus", "safety", "unsafe", "policy"]
        if guardrailHits.contains(where: blob.contains) {
            return .guardrail
        }
        let overflowHits = [
            "context window", "context length", "exceededcontextwindow",
            "exceeded context", "too long"
        ]
        if overflowHits.contains(where: blob.contains) {
            return .contextTooLong
        }
        return .other(localized)
    }
}
