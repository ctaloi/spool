import AppIntents
import Foundation

/// Fetches the current top Hacker News story, pulls the article body, and
/// runs the on-device Apple Intelligence summarizer. Surfaced as a Siri
/// Shortcut + Spotlight entry so you can ask the phone "summarize the top
/// Spool story" without opening the app.
struct SummarizeTopStoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Summarize Top HN Story"
    static let description = IntentDescription(
        "Fetches the current top Hacker News story and generates an on-device AI summary."
    )
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        guard case .available = SummaryService.shared.availability else {
            throw IntentError.unavailable(SummaryService.shared.availability.userMessage)
        }

        let ids = try await HNAPI.shared.storyIDs(for: .top)
        guard let topID = ids.first else {
            throw IntentError.noStories
        }
        let item = try await HNAPI.shared.item(id: topID)
        guard let urlString = item.url, let url = URL(string: urlString) else {
            throw IntentError.noURL
        }

        let articleText = try await ArticleFetcher.shared.fetchText(from: url)
        guard !articleText.isEmpty else {
            throw IntentError.emptyArticle
        }

        let stream = SummaryService.shared.summarize(
            title: item.title ?? "",
            articleText: articleText
        )
        var summary = ""
        for try await partial in stream {
            summary = partial
        }

        let title = item.title ?? "the top story"
        let dialog = IntentDialog("\(title)\n\n\(summary)")
        return .result(value: summary, dialog: dialog)
    }

    enum IntentError: LocalizedError {
        case unavailable(String)
        case noStories
        case noURL
        case emptyArticle

        var errorDescription: String? {
            switch self {
            case .unavailable(let m): return m
            case .noStories:          return "No top stories available right now."
            case .noURL:              return "The top story is text-only — nothing to summarize."
            case .emptyArticle:       return "Couldn't extract any text from the article."
            }
        }
    }
}

struct SpoolShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SummarizeTopStoryIntent(),
            phrases: [
                "Summarize the top \(.applicationName) story",
                "What's on \(.applicationName) right now"
            ],
            shortTitle: "Top HN Story",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: WhatsTrendingIntent(),
            phrases: [
                "What's trending on \(.applicationName)",
                "Show me trending \(.applicationName) stories"
            ],
            shortTitle: "Trending",
            systemImageName: "chart.line.uptrend.xyaxis"
        )
    }
}
