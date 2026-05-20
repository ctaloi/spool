import Testing
import Foundation
@testable import Spool

/// Pure tests for the data models — MainFeedSource display
/// properties, SpooledStory computed fields, etc. No SwiftData
/// container needed for any of these; they're all reading model
/// properties or computed accessors.
struct MainFeedSourceTests {

    @Test func displayTitleCoversEveryCase() {
        // Every case should have a non-empty, sensible display title.
        // The sidebar and the navbar large title both lean on this,
        // so missing one means a blank screen heading.
        let cases: [(MainFeedSource, String)] = [
            (.category(.top), "Top Stories"),
            (.category(.new), "New Stories"),
            (.category(.best), "Best Stories"),
            (.category(.ask), "Ask HN"),
            (.category(.show), "Show HN"),
            (.category(.job), "Jobs"),
            (.trending, "Trending"),
            (.bestOf(.today), "Best of Today"),
            (.bestOf(.week), "Best of This Week"),
            (.bestOf(.month), "Best of This Month"),
            (.bestOf(.year), "Best of This Year"),
            (.saved, "Saved"),
            (.spool, "Spool"),
            (.archive, "Archive"),
            (.following, "Following"),
            (.mentions, "Mentions"),
        ]
        for (source, expected) in cases {
            #expect(source.displayTitle == expected,
                    "displayTitle for \(source) should be \"\(expected)\"")
        }
    }

    @Test func everyCaseHasIconSymbol() {
        // An empty icon string would render as a missing-glyph
        // placeholder in the sidebar — visually broken.
        let sources: [MainFeedSource] = [
            .category(.top), .trending, .bestOf(.today),
            .saved, .spool, .archive, .following, .mentions,
        ]
        for source in sources {
            #expect(!source.icon.isEmpty,
                    "icon for \(source) must not be empty")
        }
    }

    @Test func searchSupportedOnlyOnCategoryFeeds() {
        #expect(MainFeedSource.category(.top).supportsSearch == true)
        #expect(MainFeedSource.trending.supportsSearch == false)
        #expect(MainFeedSource.bestOf(.today).supportsSearch == false)
        #expect(MainFeedSource.saved.supportsSearch == false)
        #expect(MainFeedSource.spool.supportsSearch == false)
        #expect(MainFeedSource.archive.supportsSearch == false)
        #expect(MainFeedSource.following.supportsSearch == false)
        #expect(MainFeedSource.mentions.supportsSearch == false)
    }
}

struct SpooledStoryTests {

    private func makeStory(
        article: String? = nil,
        thread: String? = nil
    ) -> SpooledStory {
        SpooledStory(
            id: 1,
            title: "Test",
            urlString: nil,
            author: "tester",
            score: 1,
            descendants: 0,
            cachedArticleSummary: article,
            cachedThreadSummary: thread
        )
    }

    @Test func playlistScriptNilWhenBothSummariesMissing() {
        #expect(makeStory().playlistScript == nil)
    }

    @Test func playlistScriptIncludesArticleOnly() {
        let script = makeStory(article: "Apples are red.").playlistScript
        #expect(script?.contains("Apples are red.") == true)
        #expect(script?.contains("Article summary") == true)
        #expect(script?.contains("Discussion") == false)
    }

    @Test func playlistScriptIncludesThreadOnly() {
        let script = makeStory(thread: "People disagree.").playlistScript
        #expect(script?.contains("People disagree.") == true)
        #expect(script?.contains("Discussion") == true)
        #expect(script?.contains("Article summary") == false)
    }

    @Test func playlistScriptCombinesBoth() {
        let script = makeStory(
            article: "Article body.",
            thread: "Thread body."
        ).playlistScript
        let s = script ?? ""
        #expect(s.contains("Article summary"))
        #expect(s.contains("Article body."))
        #expect(s.contains("Discussion"))
        #expect(s.contains("Thread body."))
        // Article cue should precede discussion cue in the spoken
        // script — otherwise the listener hears comments first.
        if let articleRange = s.range(of: "Article body."),
           let threadRange = s.range(of: "Thread body.") {
            #expect(articleRange.lowerBound < threadRange.lowerBound)
        }
    }

    @Test func playlistScriptIgnoresEmptyStrings() {
        let script = makeStory(article: "", thread: "").playlistScript
        #expect(script == nil)
    }

    @Test func estimatedDurationZeroForEmptyScript() {
        #expect(makeStory().estimatedDurationSeconds == 0)
    }

    @Test func estimatedDurationHasFloorForVeryShortScript() {
        // Floor of 15s prevents a 1-character summary from claiming
        // it's 0 seconds long.
        let short = makeStory(article: "Yes.")
        #expect(short.estimatedDurationSeconds >= 15)
    }

    @Test func estimatedDurationScalesWithLength() {
        let long = makeStory(
            article: String(repeating: "word ", count: 200)
        )
        let short = makeStory(article: "Tiny.")
        #expect(long.estimatedDurationSeconds > short.estimatedDurationSeconds)
    }
}
