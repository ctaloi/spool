import Testing
import Foundation
@testable import Spool

/// HNItem rides through every layer of the app. These tests cover
/// the JSON decode path (Firebase HN API shapes) and the computed
/// helpers (`host`, `date`, `isDeletedOrDead`).
struct HNItemTests {

    @Test func decodesMinimalStory() throws {
        let json = #"""
        {
            "id": 1,
            "type": "story",
            "by": "pg",
            "time": 1160418111,
            "title": "Y Combinator",
            "url": "https://ycombinator.com",
            "score": 57,
            "descendants": 15,
            "kids": [9, 87, 11],
            "text": null,
            "parent": null,
            "deleted": null,
            "dead": null,
            "parts": null
        }
        """#.data(using: .utf8)!
        let item = try JSONDecoder().decode(HNItem.self, from: json)
        #expect(item.id == 1)
        #expect(item.title == "Y Combinator")
        #expect(item.by == "pg")
        #expect(item.score == 57)
    }

    @Test func decodesItemWithMissingOptionalFields() throws {
        // Firebase regularly omits fields that aren't set. The
        // model treats every non-id field as Optional, so this
        // should parse without throwing.
        let json = #"""
        {"id": 42, "type": "comment", "by": "user", "time": 100}
        """#.data(using: .utf8)!
        let item = try JSONDecoder().decode(HNItem.self, from: json)
        #expect(item.id == 42)
        #expect(item.text == nil)
        #expect(item.score == nil)
        #expect(item.kids == nil)
    }

    @Test func hostStripsWWWPrefix() {
        let item = HNItem(
            id: 1, type: "story", by: nil, time: nil, text: nil,
            url: "https://www.example.com/article", title: "T",
            score: nil, descendants: nil, kids: nil, parent: nil,
            deleted: nil, dead: nil, parts: nil
        )
        #expect(item.host == "example.com")
    }

    @Test func hostPreservesNonWWWPrefix() {
        let item = HNItem(
            id: 1, type: "story", by: nil, time: nil, text: nil,
            url: "https://news.ycombinator.com/item?id=1", title: "T",
            score: nil, descendants: nil, kids: nil, parent: nil,
            deleted: nil, dead: nil, parts: nil
        )
        #expect(item.host == "news.ycombinator.com")
    }

    @Test func hostNilWhenNoURL() {
        let item = HNItem(
            id: 1, type: "story", by: nil, time: nil, text: "Ask HN body",
            url: nil, title: "Ask HN: why",
            score: nil, descendants: nil, kids: nil, parent: nil,
            deleted: nil, dead: nil, parts: nil
        )
        #expect(item.host == nil)
    }

    @Test func dateNilWhenNoTime() {
        let item = HNItem(
            id: 1, type: nil, by: nil, time: nil, text: nil,
            url: nil, title: nil, score: nil, descendants: nil,
            kids: nil, parent: nil, deleted: nil, dead: nil, parts: nil
        )
        #expect(item.date == nil)
    }

    @Test func dateConvertsUnixTimestamp() {
        let item = HNItem(
            id: 1, type: nil, by: nil, time: 1_700_000_000,
            text: nil, url: nil, title: nil, score: nil,
            descendants: nil, kids: nil, parent: nil,
            deleted: nil, dead: nil, parts: nil
        )
        #expect(item.date == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func isDeletedOrDeadFlagsBothPaths() {
        let normal = HNItem(
            id: 1, type: nil, by: nil, time: nil, text: nil, url: nil,
            title: nil, score: nil, descendants: nil, kids: nil,
            parent: nil, deleted: false, dead: false, parts: nil
        )
        let deleted = HNItem(
            id: 2, type: nil, by: nil, time: nil, text: nil, url: nil,
            title: nil, score: nil, descendants: nil, kids: nil,
            parent: nil, deleted: true, dead: false, parts: nil
        )
        let dead = HNItem(
            id: 3, type: nil, by: nil, time: nil, text: nil, url: nil,
            title: nil, score: nil, descendants: nil, kids: nil,
            parent: nil, deleted: false, dead: true, parts: nil
        )
        #expect(normal.isDeletedOrDead == false)
        #expect(deleted.isDeletedOrDead == true)
        #expect(dead.isDeletedOrDead == true)
    }

    @Test func nilDeletedDeadTreatedAsNormal() {
        let item = HNItem(
            id: 1, type: nil, by: nil, time: nil, text: nil, url: nil,
            title: nil, score: nil, descendants: nil, kids: nil,
            parent: nil, deleted: nil, dead: nil, parts: nil
        )
        #expect(item.isDeletedOrDead == false)
    }
}

struct HNStoryFeedTests {

    @Test func everyCaseHasNonEmptyTitle() {
        for feed in HNStoryFeed.allCases {
            #expect(!feed.title.isEmpty, "title for \(feed) should not be empty")
        }
    }

    @Test func navigationTitleHasHNSuffixForAskAndShow() {
        #expect(HNStoryFeed.ask.navigationTitle == "Ask HN")
        #expect(HNStoryFeed.show.navigationTitle == "Show HN")
        #expect(HNStoryFeed.top.navigationTitle == "Top")
        #expect(HNStoryFeed.new.navigationTitle == "New")
    }

    @Test func everyCaseHasUniqueEndpoint() {
        let endpoints = HNStoryFeed.allCases.map(\.endpoint)
        #expect(Set(endpoints).count == endpoints.count)
    }

    @Test func endpointMatchesFirebaseConvention() {
        // Firebase HN API endpoints all end in "stories".
        for feed in HNStoryFeed.allCases {
            #expect(feed.endpoint.hasSuffix("stories"),
                    "\(feed) endpoint should end with 'stories'")
        }
    }

    @Test func everyCaseHasIconSymbol() {
        for feed in HNStoryFeed.allCases {
            #expect(!feed.icon.isEmpty)
        }
    }
}
