import Foundation

/// Aggregates recent submissions across all followed users into a
/// single chronological feed. No background polling — fetches on
/// demand when the user opens the Following source.
@MainActor
final class FollowingFeedViewModel: ObservableObject {
    @Published private(set) var items: [HNItem] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    func load(usernames: [String]) async {
        guard !usernames.isEmpty else {
            items = []
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // Fan out one Algolia request per followed user, then
            // merge and sort chronologically.
            var collected: [HNItem] = []
            try await withThrowingTaskGroup(of: [HNItem].self) { group in
                for username in usernames {
                    group.addTask {
                        let submissions = try await HNUserService.shared.submissions(by: username)
                        return submissions.map { sub in
                            HNItem(
                                id: sub.id,
                                type: "story",
                                by: username,
                                time: sub.createdAt?.timeIntervalSince1970,
                                text: nil,
                                url: sub.url,
                                title: sub.title,
                                score: sub.points,
                                descendants: sub.numComments,
                                kids: nil,
                                parent: nil,
                                deleted: nil,
                                dead: nil,
                                parts: nil
                            )
                        }
                    }
                }
                for try await batch in group {
                    collected.append(contentsOf: batch)
                }
            }
            // Newest first.
            self.items = collected.sorted {
                ($0.time ?? 0) > ($1.time ?? 0)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
