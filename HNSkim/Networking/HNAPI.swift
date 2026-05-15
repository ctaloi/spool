import Foundation

actor HNAPI {
    static let shared = HNAPI()

    private let base = URL(string: "https://hacker-news.firebaseio.com/v0")!
    private let session: URLSession
    private let decoder = JSONDecoder()

    /// NSCache evicts under memory pressure automatically and caps itself,
    /// so we don't grow unbounded for the process lifetime.
    private let itemCache: NSCache<NSNumber, BoxedItem> = {
        let c = NSCache<NSNumber, BoxedItem>()
        c.countLimit = 500
        return c
    }()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func storyIDs(for feed: HNStoryFeed) async throws -> [Int] {
        let url = base.appendingPathComponent("\(feed.endpoint).json")
        let (data, _) = try await session.data(from: url)
        return try decoder.decode([Int].self, from: data)
    }

    func item(id: Int) async throws -> HNItem {
        if let cached = itemCache.object(forKey: NSNumber(value: id)) {
            return cached.item
        }
        let url = base.appendingPathComponent("item/\(id).json")
        let (data, _) = try await session.data(from: url)
        let item = try decoder.decode(HNItem.self, from: data)
        itemCache.setObject(BoxedItem(item), forKey: NSNumber(value: id))
        return item
    }

    /// Fetch many items concurrently, preserving the input order.
    func items(ids: [Int]) async throws -> [HNItem] {
        try await withThrowingTaskGroup(of: (Int, HNItem).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask { [self] in
                    let item = try await self.item(id: id)
                    return (index, item)
                }
            }
            var buffer: [(Int, HNItem)] = []
            for try await pair in group { buffer.append(pair) }
            return buffer.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }
}

/// NSCache requires class values, so we box `HNItem` (a struct).
private final class BoxedItem {
    let item: HNItem
    init(_ item: HNItem) { self.item = item }
}
