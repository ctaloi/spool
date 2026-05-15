import AppIntents
import Foundation

/// Returns a brief "what's trending right now" string — the top 5
/// titles by velocity. No app open required.
struct WhatsTrendingIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Trending on HN"
    static let description = IntentDescription(
        "Returns a quick rundown of the top trending Hacker News stories."
    )
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        // Algolia's points-ranked endpoint, narrowed to the last 24
        // hours, gives a fair "what's hot" without needing local
        // snapshot history.
        let page = try await HNSearchService.shared.fetch(
            .bestOf(.today),
            page: 0,
            hitsPerPage: 5
        )
        guard !page.stories.isEmpty else {
            return .result(value: "Nothing trending yet today.",
                           dialog: "Nothing trending yet today.")
        }
        let lines = page.stories.prefix(5).enumerated().map { idx, story in
            "\(idx + 1). \(story.title ?? "(untitled)")"
        }
        let body = lines.joined(separator: "\n")
        return .result(value: body, dialog: IntentDialog("Trending right now:\n\n\(body)"))
    }
}

/// Reads today's daily digest aloud via Siri. Generates fresh on
/// demand using the same DigestViewModel pipeline the in-app card
/// uses.
struct ReadTodaysDigestIntent: AppIntent {
    static let title: LocalizedStringResource = "Read Today's HN Digest"
    static let description = IntentDescription(
        "Generates and speaks a short summary of today's top Hacker News stories."
    )
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        guard case .available = SummaryService.shared.availability else {
            throw NSError(
                domain: "ReadTodaysDigestIntent",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: SummaryService.shared.availability.userMessage]
            )
        }
        let ids = try await HNAPI.shared.storyIDs(for: .top)
        let stories = try await HNAPI.shared.items(ids: Array(ids.prefix(15)))
        let headlines = stories
            .compactMap { $0.title }
            .enumerated()
            .map { "\($0 + 1). \($1)" }
            .joined(separator: "\n")

        let stream = SummaryService.shared.digestRecentStories(headlines: headlines)
        var digest = ""
        for try await partial in stream {
            digest = partial
        }
        return .result(value: digest, dialog: IntentDialog(stringLiteral: digest))
    }
}
