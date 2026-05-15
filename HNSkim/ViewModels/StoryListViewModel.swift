import Foundation
import SwiftData
import SwiftUI

@MainActor
final class StoryListViewModel: ObservableObject {
    @Published var feed: HNStoryFeed = .top {
        didSet { Task { await reload() } }
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
        guard index >= threshold, stories.count < allIDs.count else { return }
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

    func share(_ story: HNItem) {
        guard let urlString = story.url, let url = URL(string: urlString) else { return }
        let activityVC = UIActivityViewController(
            activityItems: [url, story.title ?? ""],
            applicationActivities: nil
        )
        // Find the key window to present from
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityVC, animated: true)
        }
    }
}
