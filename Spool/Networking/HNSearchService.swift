import Foundation
import os.log

private let algoliaLog = Logger(subsystem: "news.getspool.app", category: "Algolia")

/// Sort direction for Algolia queries. Maps to the two Algolia endpoints
/// — `/search` (by relevance, which for HN means by points) and
/// `/search_by_date` (chronological).
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

/// Fixed-window time bucket used by the Best-of section in the sidebar.
/// Each case resolves to a `created_at_i` lower bound (in seconds since
/// epoch) when the user opens it.
enum BestOfWindow: String, CaseIterable, Identifiable {
    case today, week, month, year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .week:  return "This Week"
        case .month: return "This Month"
        case .year:  return "This Year"
        }
    }

    var icon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .week:  return "calendar"
        case .month: return "calendar.badge.clock"
        case .year:  return "rosette"
        }
    }

    /// Lower bound (created_at_i seconds since epoch) for the window.
    func sinceTimestamp(relativeTo now: Date = .now) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let start: Date
        switch self {
        case .today:
            start = calendar.startOfDay(for: now)
        case .week:
            start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .month:
            start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .year:
            start = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        }
        return Int(start.timeIntervalSince1970)
    }
}

/// What the feed is showing — drives both the Algolia query and the
/// view's title/empty state. Adding a new kind here is cheap: thread it
/// through `urlComponents` and add a UI entry point.
enum AlgoliaFeedKind: Hashable, Sendable {
    case search(query: String, sort: HNSearchSort)
    case domain(String)
    case bestOf(BestOfWindow)
}

struct HNSearchPage {
    let stories: [HNItem]
    let page: Int
    let totalPages: Int
    let totalHits: Int
    var hasMore: Bool { page + 1 < totalPages }
}

/// A comment authored by the signed-in user, surfaced by an Algolia
/// author search. Holds just enough context to fetch fresh kids and
/// render a Mentions row without re-walking the comment tree to the
/// story root.
struct AuthoredComment: Identifiable, Sendable, Hashable {
    let id: Int
    let text: String?
    let createdAt: Date
    let parentID: Int?
    let storyID: Int
    let storyTitle: String?
}

actor HNSearchService {
    static let shared = HNSearchService()

    private let base = URL(string: "https://hn.algolia.com/api/v1")!
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(
        _ kind: AlgoliaFeedKind,
        page: Int = 0,
        hitsPerPage: Int = 30
    ) async throws -> HNSearchPage {
        let url = urlComponents(for: kind, page: page, hitsPerPage: hitsPerPage).url!
        algoliaLog.debug("→ \(url.absoluteString, privacy: .public)")
        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let payload = try decoder.decode(AlgoliaResponse.self, from: data)
        let stories = payload.hits.compactMap(\.asHNItem)
        let filtered = Self.postFilter(stories, kind: kind)
        algoliaLog.debug("← status=\(status, privacy: .public) nbHits=\(payload.nbHits, privacy: .public) hits=\(payload.hits.count, privacy: .public) decoded=\(stories.count, privacy: .public) filtered=\(filtered.count, privacy: .public)")
        return HNSearchPage(
            stories: filtered,
            page: payload.page,
            totalPages: payload.nbPages,
            totalHits: payload.nbHits
        )
    }

    /// Convenience wrapper preserving the original `search(query:sort:)`
    /// signature for callers that haven't migrated to `fetch(_:)` yet.
    func search(
        query: String,
        sort: HNSearchSort,
        page: Int = 0,
        hitsPerPage: Int = 30
    ) async throws -> HNSearchPage {
        try await fetch(.search(query: query, sort: sort), page: page, hitsPerPage: hitsPerPage)
    }

    /// List the user's most recent comments via Algolia, newest first.
    /// Drives the Mentions feed — each returned comment is a candidate
    /// "thread you participated in" whose kids we then walk for replies.
    /// `story_title` is populated on the Algolia hit, so we capture it
    /// here and avoid an extra root-story fetch downstream.
    func searchCommentsByAuthor(
        _ username: String,
        hitsPerPage: Int = 30
    ) async throws -> [AuthoredComment] {
        var components = URLComponents(
            url: base.appendingPathComponent("search_by_date"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "tags", value: "comment,author_\(username)"),
            URLQueryItem(name: "hitsPerPage", value: String(hitsPerPage)),
        ]
        let (data, _) = try await session.data(from: components.url!)
        let payload = try decoder.decode(AlgoliaResponse.self, from: data)
        return payload.hits.compactMap(\.asAuthoredComment)
    }

    private func urlComponents(
        for kind: AlgoliaFeedKind,
        page: Int,
        hitsPerPage: Int
    ) -> URLComponents {
        var endpoint: String
        var items: [URLQueryItem] = [
            URLQueryItem(name: "tags", value: "story"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "hitsPerPage", value: String(hitsPerPage))
        ]

        switch kind {
        case .search(let query, let sort):
            endpoint = sort.endpoint
            items.append(URLQueryItem(name: "query", value: query))
        case .domain(let host):
            // Algolia indexes the URL — we match on the host substring,
            // then post-filter for an exact host match below.
            endpoint = "search_by_date"
            items.append(URLQueryItem(name: "query", value: host))
            items.append(URLQueryItem(name: "restrictSearchableAttributes", value: "url"))
        case .bestOf(let window):
            // Sort by points desc using the points-ranked endpoint; clip
            // to the time window with a numeric filter.
            endpoint = "search"
            let since = window.sinceTimestamp()
            items.append(URLQueryItem(
                name: "numericFilters",
                value: "created_at_i>\(since)"
            ))
        }

        var components = URLComponents(
            url: base.appendingPathComponent(endpoint),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = items
        return components
    }

    /// Algolia's URL search matches substrings; a query for `nytimes.com`
    /// will surface `mynytimes.com` and `nytimes.com.cn`. Enforce a strict
    /// host match in code so the Domain feed actually means "stories from
    /// this host."
    private static func postFilter(_ stories: [HNItem], kind: AlgoliaFeedKind) -> [HNItem] {
        guard case .domain(let target) = kind else { return stories }
        let normalizedTarget = normalizeHost(target)
        return stories.filter { story in
            guard let host = story.host else { return false }
            return normalizeHost(host) == normalizedTarget
        }
    }

    private static func normalizeHost(_ host: String) -> String {
        let lower = host.lowercased()
        return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
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
    let commentText: String?
    let parentID: Int?
    let storyID: Int?
    let storyTitle: String?
    let numComments: Int?
    let createdAtI: TimeInterval?
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case objectID
        case title
        case url
        case author
        case points
        case storyText   = "story_text"
        case commentText = "comment_text"
        case parentID    = "parent_id"
        case storyID     = "story_id"
        case storyTitle  = "story_title"
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
            dead: nil,
            parts: nil
        )
    }

    private var inferredType: String {
        guard let tags else { return "story" }
        if tags.contains("job")   { return "job" }
        if tags.contains("poll")  { return "poll" }
        return "story"
    }

    /// Maps a `comment` hit into the public AuthoredComment shape.
    /// Returns nil for non-comment hits — defends against a stray hit
    /// shape changing under us.
    var asAuthoredComment: AuthoredComment? {
        guard let id = Int(objectID),
              let storyID,
              let createdAtI
        else { return nil }
        let isComment = tags?.contains("comment") ?? false
        guard isComment else { return nil }
        return AuthoredComment(
            id: id,
            text: commentText,
            createdAt: Date(timeIntervalSince1970: createdAtI),
            parentID: parentID,
            storyID: storyID,
            storyTitle: storyTitle
        )
    }
}
