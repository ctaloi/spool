import Testing
import Foundation
@testable import Spool

/// Tests the Firebase HN API client via URLProtocol stubbing — no
/// live network. Covers the three public surface methods plus the
/// item-cache behavior.
struct HNAPITests {

    private func makeAPI() -> HNAPI {
        URLProtocolStub.reset()
        return HNAPI(session: URLProtocolStub.makeSession())
    }

    // MARK: - storyIDs

    @Test func storyIDsDecodesFlatIntArray() async throws {
        let api = makeAPI()
        URLProtocolStub.respond(
            toURLContaining: "topstories.json",
            with: #"[1, 2, 3, 4, 5]"#.data(using: .utf8)!
        )
        let ids = try await api.storyIDs(for: .top)
        #expect(ids == [1, 2, 3, 4, 5])
    }

    @Test func storyIDsHitsCorrectEndpointPerFeed() async throws {
        for feed in HNStoryFeed.allCases {
            let api = makeAPI()
            URLProtocolStub.respond(
                toURLContaining: "\(feed.endpoint).json",
                with: "[42]".data(using: .utf8)!
            )
            let ids = try await api.storyIDs(for: feed)
            #expect(ids == [42], "feed \(feed) should hit its own endpoint")
        }
    }

    @Test func storyIDsThrowsOnMalformedJSON() async {
        let api = makeAPI()
        URLProtocolStub.respond(
            toURLContaining: "topstories.json",
            with: "{not an array}".data(using: .utf8)!
        )
        await #expect(throws: (any Error).self) {
            _ = try await api.storyIDs(for: .top)
        }
    }

    // MARK: - item

    @Test func itemDecodesSingleStory() async throws {
        let api = makeAPI()
        URLProtocolStub.respond(
            toURLContaining: "item/123.json",
            with: #"{"id":123,"type":"story","title":"Hello","by":"pg","time":1700000000,"score":42}"#
                .data(using: .utf8)!
        )
        let item = try await api.item(id: 123)
        #expect(item.id == 123)
        #expect(item.title == "Hello")
        #expect(item.by == "pg")
    }

    @Test func itemCachesSecondLookup() async throws {
        let api = makeAPI()
        var hits = 0
        URLProtocolStub.respond(toURLContaining: "item/7.json") { _ in
            hits += 1
            let json = #"{"id":7,"type":"story","title":"Cached","time":1700000000}"#
            return (HTTPURLResponse(url: URL(string: "x:")!,
                                     statusCode: 200,
                                     httpVersion: nil,
                                     headerFields: nil)!,
                    json.data(using: .utf8)!)
        }
        _ = try await api.item(id: 7)
        _ = try await api.item(id: 7)
        _ = try await api.item(id: 7)
        #expect(hits == 1, "subsequent calls should hit the cache, not the network")
    }

    // MARK: - items (batch)

    @Test func itemsBatchFetchPreservesOrder() async throws {
        let api = makeAPI()
        for id in [10, 20, 30] {
            URLProtocolStub.respond(
                toURLContaining: "item/\(id).json",
                with: #"{"id":\#(id),"type":"story","title":"\#(id)","time":1700000000}"#
                    .data(using: .utf8)!
            )
        }
        // Request order is intentionally non-monotonic — output must
        // still match the input order, not concurrent completion.
        let items = try await api.items(ids: [30, 10, 20])
        #expect(items.map(\.id) == [30, 10, 20])
    }

    @Test func itemsBatchEmptyInputReturnsEmpty() async throws {
        let api = makeAPI()
        let items = try await api.items(ids: [])
        #expect(items.isEmpty)
    }

    @Test func itemsBatchPropagatesFirstError() async {
        let api = makeAPI()
        // Only register one of two; the second triggers the "no handler"
        // failure path inside URLProtocolStub.
        URLProtocolStub.respond(
            toURLContaining: "item/100.json",
            with: #"{"id":100,"type":"story","time":1700000000}"#.data(using: .utf8)!
        )
        await #expect(throws: (any Error).self) {
            _ = try await api.items(ids: [100, 999])
        }
    }
}
