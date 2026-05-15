import UIKit

/// Generic image cache + fetcher. Two-tier caching: NSCache for in-memory
/// (evicts under memory pressure), URLCache for disk so images survive
/// app restarts. Coalesces concurrent requests for the same URL via an
/// in-flight task map so a 30-row feed populating thumbnails doesn't
/// fan out into 30 duplicate downloads if the same image is referenced
/// twice in the visible window.
actor ImageFetcher {
    static let shared = ImageFetcher()

    private let memoryCache: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.countLimit = 200
        c.totalCostLimit = 24 * 1024 * 1024 // ~24 MB of decoded thumbs
        return c
    }()

    private let session: URLSession = {
        // ~64 MB on-disk image cache; URLSession negotiates 304s with the
        // origin and serves locally when fresh.
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 64 * 1024 * 1024,
            directory: nil
        )
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    private var inFlight: [URL: Task<UIImage, Error>] = [:]

    func image(for url: URL) async throws -> UIImage {
        if let hit = memoryCache.object(forKey: url as NSURL) {
            return hit
        }
        if let existing = inFlight[url] {
            // Split the suspension explicitly — `Task.result` IS async,
            // but SourceKit's flow analysis through `try await x.result.get()`
            // mis-reports "no async operations within await." Storing the
            // awaited Result first makes the suspension unambiguous.
            let result = await existing.result
            return try result.get()
        }
        let task = Task<UIImage, Error> {
            defer { Task { await self.clearInFlight(url) } }
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            guard let image = UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            let cost = data.count
            self.memoryCache.setObject(image, forKey: url as NSURL, cost: cost)
            return image
        }
        inFlight[url] = task
        return try await task.value
    }

    private func clearInFlight(_ url: URL) {
        inFlight[url] = nil
    }
}
