import Testing
import Foundation
@testable import Spool

/// AppRouter parses deep links from Spotlight, widgets, and
/// notifications. The router lives outside the view layer so
/// these tests just exercise `handle(_:)` + `consume…()` directly.
@MainActor
struct AppRouterTests {

    @Test func storyDeepLinkSetsPendingID() {
        let router = AppRouter()
        router.handle(URL(string: "spool://story/12345")!)
        #expect(router.pendingStoryID == 12345)
    }

    @Test func feedDeepLinkSetsPendingSource() {
        let router = AppRouter()
        router.handle(URL(string: "spool://feed/trending")!)
        #expect(router.pendingFeedSource == "trending")
    }

    @Test func consumeStoryIDClearsAfterRead() {
        let router = AppRouter()
        router.handle(URL(string: "spool://story/42")!)
        #expect(router.consumeStoryID() == 42)
        // One-shot: subsequent consume reads nil.
        #expect(router.consumeStoryID() == nil)
        #expect(router.pendingStoryID == nil)
    }

    @Test func consumeFeedSourceClearsAfterRead() {
        let router = AppRouter()
        router.handle(URL(string: "spool://feed/saved")!)
        #expect(router.consumeFeedSource() == "saved")
        #expect(router.consumeFeedSource() == nil)
        #expect(router.pendingFeedSource == nil)
    }

    @Test func unknownSchemeIsIgnored() {
        // A `https://news.ycombinator.com/item?id=…` URL shouldn't
        // accidentally drive the deep-link state — only `spool://`
        // is for us.
        let router = AppRouter()
        router.handle(URL(string: "https://news.ycombinator.com/item?id=999")!)
        #expect(router.pendingStoryID == nil)
        #expect(router.pendingFeedSource == nil)
    }

    @Test func unknownHostIsIgnored() {
        let router = AppRouter()
        router.handle(URL(string: "spool://random/whatever")!)
        #expect(router.pendingStoryID == nil)
        #expect(router.pendingFeedSource == nil)
    }

    @Test func malformedStoryIDIsIgnored() {
        // Non-numeric path component for `story` shouldn't crash —
        // just leaves the pending state untouched.
        let router = AppRouter()
        router.handle(URL(string: "spool://story/not-a-number")!)
        #expect(router.pendingStoryID == nil)
    }

    @Test func emptyPathLeavesStateUntouched() {
        let router = AppRouter()
        router.handle(URL(string: "spool://story/")!)
        #expect(router.pendingStoryID == nil)
    }
}
