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
            instructions: SummaryPrompts.article,
            prompt: "Title: \(title)\n\nArticle text:\n\(articleText)"
        )
    }

    /// Streams a digest of the comments thread.
    func summarizeComments(
        title: String,
        comments: String
    ) -> AsyncThrowingStream<String, Error> {
        makeAppleStream(
            instructions: SummaryPrompts.comments,
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
            instructions: SummaryPrompts.threadQA,
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
            instructions: SummaryPrompts.articleQA,
            prompt: prompt
        )
    }

    /// Audio-tuned article summary for the Spool playlist. The
    /// model is told this is being read aloud, so the output is
    /// conversational prose with no markdown / bullets / labels.
    /// Section transitions become full sentences.
    func summarizeArticleForAudio(
        title: String,
        articleText: String
    ) -> AsyncThrowingStream<String, Error> {
        makeAppleStream(
            instructions: SummaryPrompts.articleAudio,
            prompt: "Title: \(title)\n\nArticle text:\n\(articleText)"
        )
    }

    /// Audio-tuned comments summary for the Spool playlist.
    /// Same conversational pivot — no markdown headings ("Sentiment",
    /// "Themes") that sound clinical when spoken.
    func summarizeCommentsForAudio(
        title: String,
        comments: String
    ) -> AsyncThrowingStream<String, Error> {
        makeAppleStream(
            instructions: SummaryPrompts.commentsAudio,
            prompt: "Story: \(title)\n\nComments thread (oldest top-level first; indentation shows replies):\n\(comments)"
        )
    }

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
