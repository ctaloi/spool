import UIKit

/// Generic image cache + fetcher. Two-tier caching: NSCache for in-memory
/// (evicts under memory pressure), URLCache for disk so images survive
/// app restarts. The actor serializes cache access; concurrent fetches
/// for the same URL are deduplicated downstream by URLCache, so we
/// don't bother with an in-flight task map at this layer.
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

    func image(for url: URL) async throws -> UIImage {
        if let hit = memoryCache.object(forKey: url as NSURL) {
            return hit
        }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard let image = UIImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        memoryCache.setObject(image, forKey: url as NSURL, cost: data.count)
        return image
    }
}
