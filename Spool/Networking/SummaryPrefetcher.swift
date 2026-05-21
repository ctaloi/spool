import AVFoundation
import Foundation
import os.log
import SwiftData

/// Pre-generates AI summaries the moment the user saves or queues a
/// story. Runs in the background — by the time the user taps into
/// Saved or hits Play on the Spool playlist, the summaries
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

    // MARK: - SpooledStory: article + thread for playlist audio

    /// Schedule the same article-summary prefetch, plus a thread
    /// summary if the story has any comments. Both populate the
    /// SpooledStory's `cachedArticleSummary` / `cachedThreadSummary`
    /// so the playlist can stream audio from local data.
    static func schedulePrefetch(for queued: SpooledStory, in modelContext: ModelContext) {
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

            // Article side — independent of comments. Uses the
            // AUDIO prompt: conversational prose instead of the
            // markdown sections the in-app card consumes.
            if let url {
                let article = await Self.summarizeArticleForAudio(title: title, url: url)
                await Self.persistSpool(
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
                    let thread = await Self.summarizeThreadForAudio(title: title, transcript: transcript)
                    if let thread {
                        await Self.persistSpool(
                            articleSummary: nil,
                            threadSummary: thread,
                            storyID: storyID,
                            modelContext: modelContext
                        )
                    }
                }
            }

            // Now that both sides have settled (succeeded, failed,
            // or were skipped because there was no URL / no
            // comments), render audio against the *final* combined
            // script. Doing this once at the end — instead of after
            // each persistSpool — avoids rendering a half-script,
            // then re-rendering the full version a few seconds
            // later when the thread summary lands.
            await Self.renderAudioIfNeeded(storyID: storyID, modelContext: modelContext)
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

    /// Audio-prompt article summary — conversational prose for TTS
    /// playback. Same context-budget retry as the visual prompt.
    private static func summarizeArticleForAudio(title: String, url: URL) async -> String? {
        var charBudget = 6_000
        let minBudget = 1_500
        while true {
            do {
                let article = try await ArticleFetcher.shared
                    .fetchText(from: url, maxCharacters: charBudget)
                guard !article.isEmpty else { return nil }
                var accumulated = ""
                let stream = SummaryService.shared.summarizeArticleForAudio(
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

    /// Audio-prompt comments summary — conversational prose for
    /// TTS playback.
    private static func summarizeThreadForAudio(title: String, transcript: String) async -> String? {
        do {
            var accumulated = ""
            let stream = SummaryService.shared.summarizeCommentsForAudio(
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

    // MARK: - Internal: Spool persistence

    /// Write whichever of the two summaries we produced. Caller
    /// passes nil for the side that wasn't generated in this pass.
    /// Only stamps `cachedSummaryGeneratedAt` once both sides are
    /// non-nil (or once both sides have been attempted and one is
    /// settled-nil), so the UI can show a clean "ready" state.
    private static func persistSpool(
        articleSummary: String?,
        threadSummary: String?,
        storyID: Int,
        modelContext: ModelContext
    ) async {
        await MainActor.run {
            let descriptor = FetchDescriptor<SpooledStory>(
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
        // (Audio render now fires once after both summary sides
        // settle — see the orchestrator in schedulePrefetch — so we
        // don't re-render against a half-script that gets superseded
        // a few seconds later.)
    }

    // MARK: - Audio render

    /// Reads the latest playlistScript from the SpooledStory and
    /// renders it to a cached .caf if no cache entry exists yet.
    /// Safe to call multiple times — the cache lookup short-circuits
    /// repeat work. Errors swallowed; audio prefetch is opportunistic.
    private static func renderAudioIfNeeded(storyID: Int, modelContext: ModelContext) async {
        // Yield to any foreground request (manual Summarize tap) so
        // the LanguageModelSession + CPU is free for it. The gate
        // returns immediately when no foreground request is active.
        await PrefetchGate.shared.waitForBackgroundSlot()

        // Snapshot the script on the main actor so we don't drag the
        // SwiftData object across actor boundaries.
        let script: String? = await MainActor.run {
            let descriptor = FetchDescriptor<SpooledStory>(
                predicate: #Predicate { $0.id == storyID }
            )
            return try? modelContext.fetch(descriptor).first?.playlistScript
        }
        guard let raw = script, !raw.isEmpty else { return }
        let cleaned = MarkdownStripper.strip(raw)
        guard !cleaned.isEmpty else { return }

        let voice = SpoolPlayer.bestVoiceForCurrentLanguage()
        let rate: Float = AVSpeechUtteranceDefaultSpeechRate
        let key = AudioCacheKey(
            storyID: storyID,
            script: cleaned,
            voice: voice,
            rate: rate
        )

        // Cache hit means we already rendered this exact (story,
        // script, voice, rate) tuple — nothing to do.
        if await AudioCache.shared.lookup(key) != nil { return }

        // Claim exclusive render rights for this key. Without this
        // guard, two concurrent prefetches can both pass the lookup
        // above, both call reserveOutputURL (which removes any
        // existing file), and stomp each other mid-write — producing
        // a corrupted .caf. The second caller skips here; the first
        // will populate the cache for both.
        guard await AudioCache.shared.claimRender(key) else { return }
        defer {
            Task { await AudioCache.shared.releaseClaim(key) }
        }

        // Global "one render at a time" gate. Synth.write isn't
        // dramatically faster than real-time for higher-quality
        // voices, and running multiple renders concurrently produces
        // contention rather than throughput. With this gate, a queue
        // of 5 spooled stories renders 5×real-time total; without it,
        // they all start in parallel and finish at roughly the same
        // (long) moment.
        await AudioCache.shared.waitForRenderSlot()
        defer {
            Task { await AudioCache.shared.releaseRenderSlot() }
        }

        let outputURL: URL
        do {
            outputURL = try await AudioCache.shared.reserveOutputURL(for: key)
        } catch {
            return
        }

        let renderer = AudioRenderer()
        let renderStart = Date()
        do {
            let result = try await renderer.render(
                text: cleaned,
                voice: voice,
                rate: rate,
                to: outputURL
            )
            let elapsed = Date().timeIntervalSince(renderStart)
            audioPrefetchLog.debug(
                "Render took \(elapsed, format: .fixed(precision: 1), privacy: .public)s wall-clock for \(result.duration, format: .fixed(precision: 1), privacy: .public)s of audio (\(result.duration / max(elapsed, 0.001), format: .fixed(precision: 1), privacy: .public)× real-time)"
            )
            _ = try? await AudioCache.shared.finalize(result, key: key)
            await AudioCache.shared.enforceQuota()
            // Stamp completion on the SpooledStory so the row UI can
            // flip from "Preparing audio…" to "Ready to play" without
            // re-checking the disk cache on every render pass.
            await MainActor.run {
                let descriptor = FetchDescriptor<SpooledStory>(
                    predicate: #Predicate { $0.id == storyID }
                )
                if let queued = try? modelContext.fetch(descriptor).first {
                    queued.cachedAudioGeneratedAt = .now
                    try? modelContext.save()
                }
            }
        } catch {
            // Leave the orphaned audio file alone — the next lookup
            // will see no metadata sibling and treat it as a miss.
        }
    }
}

private let audioPrefetchLog = Logger(subsystem: "news.getspool.app", category: "AudioPrefetch")
