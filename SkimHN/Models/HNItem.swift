import Foundation

struct HNItem: Identifiable, Codable, Hashable {
    let id: Int
    let type: String?
    let by: String?
    let time: TimeInterval?
    let text: String?
    let url: String?
    let title: String?
    let score: Int?
    let descendants: Int?
    let kids: [Int]?
    let parent: Int?
    let deleted: Bool?
    let dead: Bool?
    /// For `type == "poll"`, the IDs of the `pollopt` items that make up
    /// the poll's choices. nil for any other type.
    let parts: [Int]?

    var date: Date? {
        time.map { Date(timeIntervalSince1970: $0) }
    }

    var host: String? {
        guard let url, let host = URL(string: url)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var isDeletedOrDead: Bool {
        (deleted ?? false) || (dead ?? false)
    }
}

enum HNStoryFeed: String, CaseIterable, Identifiable {
    case top, new, best, ask, show, job

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top:  return "Top"
        case .new:  return "New"
        case .best: return "Best"
        case .ask:  return "Ask"
        case .show: return "Show"
        case .job:  return "Jobs"
        }
    }

    /// Used as the navigation title. Adds "HN" where the short name is
    /// ambiguous (Ask / Show), matches the rest verbatim.
    var navigationTitle: String {
        switch self {
        case .ask:  return "Ask HN"
        case .show: return "Show HN"
        default:    return title
        }
    }

    var endpoint: String {
        switch self {
        case .top:  return "topstories"
        case .new:  return "newstories"
        case .best: return "beststories"
        case .ask:  return "askstories"
        case .show: return "showstories"
        case .job:  return "jobstories"
        }
    }

    /// SF Symbol name used in feed pickers and the iPad sidebar.
    var icon: String {
        switch self {
        case .top:  return "flame.fill"
        case .new:  return "clock.fill"
        case .best: return "star.fill"
        case .ask:  return "questionmark.bubble.fill"
        case .show: return "eye.fill"
        case .job:  return "briefcase.fill"
        }
    }
}
