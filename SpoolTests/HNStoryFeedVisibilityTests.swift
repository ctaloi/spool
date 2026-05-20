import Testing
import Foundation
@testable import Spool

/// Tests the comma-separated parse / serialize layer that backs
/// the "Visible Categories" Settings toggle. The storage format
/// is plain text (UserDefaults can't store enums directly), so
/// the parsing has to be tolerant of malformed input from older
/// versions of the app.
struct HNStoryFeedVisibilityTests {

    @Test func parsesSingleFeedKey() {
        let hidden = HNStoryFeed.hiddenSet(from: "ask")
        #expect(hidden == [.ask])
    }

    @Test func parsesMultipleFeedKeys() {
        let hidden = HNStoryFeed.hiddenSet(from: "ask,show,job")
        #expect(hidden == [.ask, .show, .job])
    }

    @Test func parsesEmptyStringAsEmptySet() {
        #expect(HNStoryFeed.hiddenSet(from: "") == [])
    }

    @Test func parsesIgnoresUnknownFeedKeys() {
        // A stale setting from an older app version (or a typo)
        // should be silently dropped, not crash the parse.
        let hidden = HNStoryFeed.hiddenSet(from: "ask,bogus,show")
        #expect(hidden == [.ask, .show])
    }

    @Test func parsesIgnoresWhitespaceAndEmpty() {
        // Comma sequences and trailing commas shouldn't trip the
        // parse — empty splits are just dropped.
        let hidden = HNStoryFeed.hiddenSet(from: ",ask,,show,")
        #expect(hidden == [.ask, .show])
    }

    @Test func serializesEmptySetToEmptyString() {
        #expect(HNStoryFeed.serialize(hidden: []) == "")
    }

    @Test func serializesProducesSortedOutput() {
        // Sorted output keeps the stored value stable across
        // writes; otherwise UserDefaults observers would churn
        // unnecessarily.
        let raw = HNStoryFeed.serialize(hidden: [.show, .ask, .job])
        #expect(raw == "ask,job,show")
    }

    @Test func roundtripPreservesSet() {
        let original: Set<HNStoryFeed> = [.top, .new, .best]
        let raw = HNStoryFeed.serialize(hidden: original)
        let parsed = HNStoryFeed.hiddenSet(from: raw)
        #expect(parsed == original)
    }

    @Test func visibleHonorsHidden() {
        let visible = HNStoryFeed.visible(hiddenRaw: "ask,show")
        #expect(!visible.contains(.ask))
        #expect(!visible.contains(.show))
        #expect(visible.contains(.top))
        #expect(visible.contains(.new))
    }

    @Test func visiblePreservesDeclaredOrder() {
        // The declared order in `allCases` is the UI order users
        // see in the sidebar. Filtering must not re-sort.
        let visible = HNStoryFeed.visible(hiddenRaw: "new")
        let expectedOrder: [HNStoryFeed] = [.top, .best, .ask, .show, .job]
        #expect(visible == expectedOrder)
    }

    @Test func visibleWithEmptyHiddenIsAllCases() {
        #expect(HNStoryFeed.visible(hiddenRaw: "") == HNStoryFeed.allCases)
    }

    @Test func visibleWithAllHiddenIsEmpty() {
        let raw = HNStoryFeed.allCases.map(\.rawValue).joined(separator: ",")
        #expect(HNStoryFeed.visible(hiddenRaw: raw) == [])
    }
}
