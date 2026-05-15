import Foundation
import SwiftData

/// Pre-generates the AI summary for a story the moment it's saved.
/// Runs in the background so the user keeps scrolling — by the time
/// they tap into Saved, the summary is already cached on disk and
/// renders instantly, even offline.
@MainActor
enum SummaryPrefetcher {
    /// Fire-and-forget. Re-fetches the article text, runs the
    /// summarizer, writes the resulting markdown back to the saved
    /// record's `cachedSummaryText`. Idempotent — if a summary is
    /// already cached we skip.
    static func schedulePrefetch(for saved: SavedStory, in modelContext: ModelContext) {
        guard saved.cachedSummaryText == nil,
              let urlString = saved.urlString,
              let url = URL(string: urlString) else { return }
        guard SummaryService.shared.availability == .available else { return }

        let storyID = saved.id
        let title = saved.title

        Task.detached(priority: .utility) {
            await Self.run(storyID: storyID, title: title, url: url, modelContext: modelContext)
        }
    }

    private static func run(
        storyID: Int,
        title: String,
        url: URL,
        modelContext: ModelContext
    ) async {
        var charBudget = 6_000
        let minBudget = 1_500
        var accumulated = ""

        while true {
            do {
                let article = try await ArticleFetcher.shared
                    .fetchText(from: url, maxCharacters: charBudget)
                guard !article.isEmpty else { return }
                accumulated = ""
                let stream = SummaryService.shared.summarize(
                    title: title,
                    articleText: article
                )
                for try await partial in stream {
                    accumulated = partial
                }
                await Self.persist(text: accumulated, storyID: storyID, modelContext: modelContext)
                return
            } catch {
                let classified = SummaryError.classify(error)
                if case .contextTooLong = classified, charBudget > minBudget {
                    charBudget = max(minBudget, charBudget / 2)
                    continue
                }
                return
            }
        }
    }

    private static func persist(
        text: String,
        storyID: Int,
        modelContext: ModelContext
    ) async {
        await MainActor.run {
            let descriptor = FetchDescriptor<SavedStory>(
                predicate: #Predicate { $0.id == storyID }
            )
            guard let saved = try? modelContext.fetch(descriptor).first else { return }
            saved.cachedSummaryText = text
            saved.cachedSummaryGeneratedAt = .now
            try? modelContext.save()
        }
    }
}
