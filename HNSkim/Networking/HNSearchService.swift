import Foundation

/// Searches Hacker News via the free Algolia HN API.
/// https://hn.algolia.com/api
enum HNSearchSort {
    case relevance
    case newest

    var endpoint: String {
        switch self {
        case .relevance: return "search"
        case .newest:    return "search_by_date"
        }
    }
}

struct HNSearchPage {
    let stories: [HNItem]
    let page: Int
    let totalPages: Int
    let totalHits: Int
    var hasMore: Bool { page + 1 < totalPages }
}

actor HNSearchService {
    static let shared = HNSearchService()

    private let base = URL(string: "https://hn.algolia.com/api/v1")!
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(
        query: String,
        sort: HNSearchSort,
        page: Int = 0,
        hitsPerPage: Int = 30
    ) async throws -> HNSearchPage {
        var components = URLComponents(
            url: base.appendingPathComponent(sort.endpoint),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "tags", value: "story"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "hitsPerPage", value: String(hitsPerPage))
        ]
        let (data, _) = try await session.data(from: components.url!)
        let payload = try decoder.decode(AlgoliaResponse.self, from: data)
        return HNSearchPage(
            stories: payload.hits.compactMap { $0.asHNItem },
            page: payload.page,
            totalPages: payload.nbPages,
            totalHits: payload.nbHits
        )
    }
}

// MARK: - Algolia wire format

private struct AlgoliaResponse: Decodable {
    let hits: [AlgoliaHit]
    let nbHits: Int
    let page: Int
    let nbPages: Int
}

private struct AlgoliaHit: Decodable {
    let objectID: String
    let title: String?
    let url: String?
    let author: String?
    let points: Int?
    let storyText: String?
    let numComments: Int?
    let createdAtI: TimeInterval?
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case objectID
        case title
        case url
        case author
        case points
        case storyText  = "story_text"
        case numComments = "num_comments"
        case createdAtI  = "created_at_i"
        case tags        = "_tags"
    }

    var asHNItem: HNItem? {
        guard let id = Int(objectID) else { return nil }
        return HNItem(
            id: id,
            type: inferredType,
            by: author,
            time: createdAtI,
            text: storyText,
            url: url,
            title: title,
            score: points,
            descendants: numComments,
            kids: nil,
            parent: nil,
            deleted: nil,
            dead: nil
        )
    }

    private var inferredType: String {
        guard let tags else { return "story" }
        if tags.contains("job")   { return "job" }
        if tags.contains("poll")  { return "poll" }
        return "story"
    }
}
