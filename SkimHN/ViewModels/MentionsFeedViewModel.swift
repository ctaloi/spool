import Foundation
import SwiftData

/// View model for the Mentions feed — the list of replies to the
/// signed-in user's comments. No background polling; refreshes on
/// demand when the user opens the Mentions source or pulls down.
@MainActor
final class MentionsFeedViewModel: ObservableObject {
    @Published private(set) var items: [MentionRecord] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastReloadedAt: Date?

    func load(username: String?) async {
        guard let username, !username.isEmpty else {
            items = []
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            items = try await HNMentionsService.shared.fetchMentions(for: username)
            lastReloadedAt = .now
        } catch is CancellationError {
            // The user switched feeds while we were fetching. Their
            // intent is the new feed, not an error popup on Mentions.
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Number of unread items relative to a set of seen reply IDs.
    /// Computed at the view layer so SwiftData's @Query stays the
    /// source of truth — no manual sync of seen state into this VM.
    func unreadCount(seen: Set<Int>) -> Int {
        items.reduce(0) { $0 + (seen.contains($1.reply.id) ? 0 : 1) }
    }
}
