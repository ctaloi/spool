import Foundation

/// Fetches public user profile data + items authored by a user.
///
/// `/v0/user/<id>.json` provides the profile fields. Items by user come
/// from Algolia's HN index because the Firebase API only exposes raw
/// `submitted` IDs (mixed stories + comments) and we need filtering by
/// type plus chronological ordering.
actor HNUserService {
    static let shared = HNUserService()

    private let firebaseBase = URL(string: "https://hacker-news.firebaseio.com/v0")!
    private let algoliaBase = URL(string: "https://hn.algolia.com/api/v1")!
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Profile

    func user(id: String) async throws -> HNUser {
        let url = firebaseBase.appendingPathComponent("user/\(id).json")
        let (data, _) = try await session.data(from: url)
        return try decoder.decode(HNUser.self, from: data)
    }

    // MARK: - Items by author

    func submissions(by author: String, page: Int = 0) async throws -> [HNUserSubmission] {
        let response = try await fetchAlgolia(author: author, kind: "story", page: page)
        return response.hits.map { hit in
            HNUserSubmission(
                id: Int(hit.objectID) ?? 0,
                title: hit.title,
                url: hit.url,
                points: hit.points,
                numComments: hit.numComments,
                createdAt: hit.createdAtI.map { Date(timeIntervalSince1970: $0) }
            )
        }
    }

    func comments(by author: String, page: Int = 0) async throws -> [HNUserComment] {
        let response = try await fetchAlgolia(author: author, kind: "comment", page: page)
        return response.hits.compactMap { hit in
            guard let text = hit.commentText, !text.isEmpty else { return nil }
            return HNUserComment(
                id: Int(hit.objectID) ?? 0,
                storyID: hit.storyID,
                storyTitle: hit.storyTitle,
                commentText: text,
                createdAt: hit.createdAtI.map { Date(timeIntervalSince1970: $0) }
            )
        }
    }

    // MARK: - Wire format

    private func fetchAlgolia(
        author: String,
        kind: String,
        page: Int,
        hitsPerPage: Int = 30
    ) async throws -> AlgoliaUserResponse {
        var components = URLComponents(
            url: algoliaBase.appendingPathComponent("search_by_date"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "tags", value: "author_\(author),\(kind)"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "hitsPerPage", value: String(hitsPerPage))
        ]
        let (data, _) = try await session.data(from: components.url!)
        return try decoder.decode(AlgoliaUserResponse.self, from: data)
    }
}

private struct AlgoliaUserResponse: Decodable {
    let hits: [AlgoliaUserHit]
}

private struct AlgoliaUserHit: Decodable {
    let objectID: String
    let title: String?
    let url: String?
    let points: Int?
    let numComments: Int?
    let commentText: String?
    let storyID: Int?
    let storyTitle: String?
    let createdAtI: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case objectID
        case title
        case url
        case points
        case numComments  = "num_comments"
        case commentText  = "comment_text"
        case storyID      = "story_id"
        case storyTitle   = "story_title"
        case createdAtI   = "created_at_i"
    }
}
