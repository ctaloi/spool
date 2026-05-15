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

        // Fan out one Algolia request per followed user. Wrap each in
        // an inner `try?` so a single failing user (deleted account,
        // network blip, rate-limit) doesn't tank the whole feed —
        // missing users just contribute zero rows.
        var collected: [HNItem] = []
        await withTaskGroup(of: [HNItem].self) { group in
            for username in usernames {
                group.addTask {
                    do {
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
                    } catch {
                        return []
                    }
                }
            }
            for await batch in group {
                collected.append(contentsOf: batch)
            }
        }
        // Newest first.
        self.items = collected.sorted {
            ($0.time ?? 0) > ($1.time ?? 0)
        }
        if self.items.isEmpty && !usernames.isEmpty {
            // Distinguish "no recent posts" from "couldn't load anyone."
            // Today both look identical, but if we ever instrument
            // per-user error tracking, this is where the message lands.
        }
    }
}
