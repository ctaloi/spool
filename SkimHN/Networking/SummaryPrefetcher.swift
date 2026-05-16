import Foundation
import SwiftData

/// Pre-generates AI summaries the moment the user saves or queues a
/// story. Runs in the background — by the time the user taps into
/// Saved or hits Play on the Read Later playlist, the summaries
/// are already cached on disk and renders / TTS-playback are
/// instant + offline.
@MainActor
enum SummaryPrefetcher {
    // MARK: - SavedStory: article summary only

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
            await Self.runSavedArticle(
                storyID: storyID,
                title: title,
                url: url,
                modelContext: modelContext
            )
        }
    }

    // MARK: - ReadLaterStory: article + thread for playlist audio

    /// Schedule the same article-summary prefetch, plus a thread
    /// summary if the story has any comments. Both populate the
    /// ReadLaterStory's `cachedArticleSummary` / `cachedThreadSummary`
    /// so the playlist can stream audio from local data.
    static func schedulePrefetch(for queued: ReadLaterStory, in modelContext: ModelContext) {
        guard queued.cachedArticleSummary == nil else { return }
        guard SummaryService.shared.availability == .available else { return }

        let storyID = queued.id
        let title = queued.title
        let url = queued.urlString.flatMap(URL.init(string:))

        Task.detached(priority: .utility) {
            // Pull the live HN item to grab the comments transcript.
            // If the network fails the article summary still runs;
            // we just don't get a thread digest.
            let item = try? await HNAPI.shared.item(id: storyID)

            // Article side — independent of comments.
            if let url {
                let article = await Self.summarizeArticle(title: title, url: url)
                await Self.persistReadLater(
                    articleSummary: article,
                    threadSummary: nil,
                    storyID: storyID,
                    modelContext: modelContext
                )
            }

            // Thread side — needs the full comment subtree.
            if let item, let kids = item.kids, !kids.isEmpty {
                let transcript = await Self.buildCommentTranscript(rootKids: kids)
                if !transcript.isEmpty {
                    let thread = await Self.summarizeThread(title: title, transcript: transcript)
                    if let thread {
                        await Self.persistReadLater(
                            articleSummary: nil,
                            threadSummary: thread,
                            storyID: storyID,
                            modelContext: modelContext
                        )
                    }
                }
            }
        }
    }

    // MARK: - Internal: SavedStory article path

    private static func runSavedArticle(
        storyID: Int,
        title: String,
        url: URL,
        modelContext: ModelContext
    ) async {
        guard let summary = await summarizeArticle(title: title, url: url) else { return }
        await MainActor.run {
            let descriptor = FetchDescriptor<SavedStory>(
                predicate: #Predicate { $0.id == storyID }
            )
            guard let saved = try? modelContext.fetch(descriptor).first else { return }
            saved.cachedSummaryText = summary
            saved.cachedSummaryGeneratedAt = .now
            try? modelContext.save()
        }
    }

    // MARK: - Internal: shared summarization helpers

    /// Fetch + summarize article body. Returns nil on persistent
    /// failure (paywall, guardrail rejection, empty page, etc).
    /// Halves the article-text budget on context-window overflow
    /// down to a 1.5 k floor before giving up.
    private static func summarizeArticle(title: String, url: URL) async -> String? {
        var charBudget = 6_000
        let minBudget = 1_500
        while true {
            do {
                let article = try await ArticleFetcher.shared
                    .fetchText(from: url, maxCharacters: charBudget)
                guard !article.isEmpty else { return nil }
                var accumulated = ""
                let stream = SummaryService.shared.summarize(
                    title: title,
                    articleText: article
                )
                for try await partial in stream {
                    accumulated = partial
                }
                return accumulated
            } catch {
                let classified = SummaryError.classify(error)
                if case .contextTooLong = classified, charBudget > minBudget {
                    charBudget = max(minBudget, charBudget / 2)
                    continue
                }
                return nil
            }
        }
    }

    /// Summarize a flattened comment transcript. nil on failure.
    private static func summarizeThread(title: String, transcript: String) async -> String? {
        do {
            var accumulated = ""
            let stream = SummaryService.shared.summarizeComments(
                title: title,
                comments: transcript
            )
            for try await partial in stream {
                accumulated = partial
            }
            return accumulated
        } catch {
            return nil
        }
    }

    /// Build a flattened top-N comment transcript for the thread
    /// summarizer. Mirrors the live `commentsTranscript()` produced
    /// in StoryDetailViewModel but works from raw kid IDs.
    private static func buildCommentTranscript(rootKids: [Int]) async -> String {
        let topKids = Array(rootKids.prefix(30))
        var lines: [String] = []
        for id in topKids {
            guard let item = try? await HNAPI.shared.item(id: id),
                  item.deleted != true,
                  item.dead != true,
                  let text = item.text else { continue }
            let stripped = text
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#x27;", with: "'")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stripped.isEmpty {
                lines.append("- \(stripped)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Internal: ReadLater persistence

    /// Write whichever of the two summaries we produced. Caller
    /// passes nil for the side that wasn't generated in this pass.
    /// Only stamps `cachedSummaryGeneratedAt` once both sides are
    /// non-nil (or once both sides have been attempted and one is
    /// settled-nil), so the UI can show a clean "ready" state.
    private static func persistReadLater(
        articleSummary: String?,
        threadSummary: String?,
        storyID: Int,
        modelContext: ModelContext
    ) async {
        await MainActor.run {
            let descriptor = FetchDescriptor<ReadLaterStory>(
                predicate: #Predicate { $0.id == storyID }
            )
            guard let queued = try? modelContext.fetch(descriptor).first else { return }
            if let articleSummary {
                queued.cachedArticleSummary = articleSummary
            }
            if let threadSummary {
                queued.cachedThreadSummary = threadSummary
            }
            queued.cachedSummaryGeneratedAt = .now
            try? modelContext.save()
        }
    }
}
