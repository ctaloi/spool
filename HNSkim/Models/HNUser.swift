import Foundation

/// Public profile data from `/v0/user/<id>.json`.
struct HNUser: Codable, Identifiable, Hashable {
    let id: String
    let karma: Int?
    let created: TimeInterval?
    let about: String?
    let submitted: [Int]?

    var joinedDate: Date? {
        created.map { Date(timeIntervalSince1970: $0) }
    }
}

/// A story authored by a specific user, from Algolia's search-by-author
/// endpoint.
struct HNUserSubmission: Identifiable, Hashable {
    let id: Int
    let title: String?
    let url: String?
    let points: Int?
    let numComments: Int?
    let createdAt: Date?

    /// Build a transient HNItem so taps can navigate into `StoryDetailView`,
    /// which already re-fetches the live item from HNAPI.
    var asHNItem: HNItem {
        HNItem(
            id: id,
            type: "story",
            by: nil,
            time: createdAt?.timeIntervalSince1970,
            text: nil,
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
}

/// A comment authored by a specific user.
struct HNUserComment: Identifiable, Hashable {
    let id: Int
    let storyID: Int?
    let storyTitle: String?
    let commentText: String
    let createdAt: Date?
}
