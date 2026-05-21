import Foundation
import SwiftData
import SwiftUI

@MainActor
final class StoryListViewModel: ObservableObject {
    @Published var feed: HNStoryFeed = .top {
        didSet {
            guard oldValue != feed else { return }
            // Clear synchronously so the row gate sees stories.isEmpty
            // = true on the very next frame. Without this, switching
            // from one category to another briefly renders the
            // previous category's stories under the new title until
            // reload completes — looks broken.
            //
            // Reload is intentionally NOT triggered here. The caller
            // (StoryListView.loadCurrentSource) is expected to
            // `await reload()` so the load's lifetime is bracketed by
            // the same Task that drives `switchingFeed` — avoids a
            // race where the feed-switch indicator clears before
            // `isLoading` commits.
            stories = []
            errorMessage = nil
        }
    }
    @Published private(set) var stories: [HNItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    /// Timestamp of the last successful `reload()`. Drives the
    /// "refreshed Xm ago" line in the list header.
    @Published private(set) var lastReloadedAt: Date?

    private var allIDs: [Int] = []
    private let pageSize = 30

    var totalAvailable: Int { allIDs.count }

    func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            allIDs = try await HNAPI.shared.storyIDs(for: feed)
            stories = try await HNAPI.shared.items(ids: Array(allIDs.prefix(pageSize)))
            lastReloadedAt = .now
        } catch {
            if Self.isCancellation(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(current: HNItem) async {
        guard let index = stories.firstIndex(of: current) else { return }
        let threshold = stories.count - 5
        guard index >= threshold else { return }
        await loadMore()
    }

    /// Unconditional next-page load. Used by the bottom-of-list
    /// auto-pagination spinner — its visibility itself is the
    /// "should we load" signal, and we want to keep firing through
    /// filtered batches that pass nothing through the row gate.
    func loadMore() async {
        guard stories.count < allIDs.count else { return }
        let nextSlice = Array(allIDs[stories.count..<min(stories.count + pageSize, allIDs.count)])
        do {
            let more = try await HNAPI.shared.items(ids: nextSlice)
            stories.append(contentsOf: more)
        } catch {
            if Self.isCancellation(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        return false
    }

    func markAsRead(_ story: HNItem, in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<ReadStory>(
            predicate: #Predicate { $0.id == story.id }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.readAt = .now
        } else {
            modelContext.insert(ReadStory(id: story.id))
        }
    }

}
