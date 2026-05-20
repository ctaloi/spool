import Testing
import Foundation
@testable import Spool

/// classify() inspects an arbitrary Error and assigns it to one of
/// SummaryError's documented buckets. The matching is pattern-based
/// (string-contains across the error's debug / localized / type
/// description) — so tests cover the strings we look for AND verify
/// already-classified errors pass through unchanged.
struct SummaryErrorTests {

    private struct FakeError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    @Test func alreadyClassifiedPassesThrough() {
        let original = SummaryError.guardrail
        #expect(SummaryError.classify(original) == .guardrail)
    }

    @Test func guardrailFromKeywordRefus() {
        let err = FakeError(message: "Model refused to answer.")
        #expect(SummaryError.classify(err) == .guardrail)
    }

    @Test func guardrailFromKeywordSafety() {
        let err = FakeError(message: "Failed Safety check.")
        #expect(SummaryError.classify(err) == .guardrail)
    }

    @Test func guardrailFromKeywordPolicy() {
        let err = FakeError(message: "Violates the safety policy.")
        #expect(SummaryError.classify(err) == .guardrail)
    }

    @Test func contextOverflowFromKeyword() {
        let err = FakeError(message: "Exceeded context window")
        #expect(SummaryError.classify(err) == .contextTooLong)
    }

    @Test func contextOverflowFromExceededContextLength() {
        let err = FakeError(message: "Exceeded context length 8192")
        #expect(SummaryError.classify(err) == .contextTooLong)
    }

    @Test func contextOverflowFromTooLong() {
        let err = FakeError(message: "Input is too long for the model")
        #expect(SummaryError.classify(err) == .contextTooLong)
    }

    @Test func unrecognizedFallsThroughToOther() {
        let err = FakeError(message: "A wild error appears.")
        let classified = SummaryError.classify(err)
        if case .other(let msg) = classified {
            #expect(msg.contains("wild"))
        } else {
            Issue.record("Expected .other, got \(classified)")
        }
    }

    @Test func caseInsensitiveMatching() {
        let err = FakeError(message: "GUARDRAIL violation")
        #expect(SummaryError.classify(err) == .guardrail)
    }
}

// SummaryError needs Equatable for ==. Equatable conformance is just
// a typed comparison — the .other associated value is compared by
// string identity.
extension SummaryError: @retroactive Equatable {
    public static func == (lhs: SummaryError, rhs: SummaryError) -> Bool {
        switch (lhs, rhs) {
        case (.emptyArticle, .emptyArticle): return true
        case (.guardrail, .guardrail): return true
        case (.contextTooLong, .contextTooLong): return true
        case (.other(let a), .other(let b)): return a == b
        default: return false
        }
    }
}
