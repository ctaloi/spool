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

