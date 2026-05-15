import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published private(set) var results: [HNItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var totalHits: Int = 0
    @Published var sort: HNSearchSort = .relevance {
        didSet { rerunCurrentQuery() }
    }

    private(set) var query: String = ""
    private var currentPage: Int = 0
    private var hasMore: Bool = false
    private var pendingTask: Task<Void, Never>?

    /// Called from the view as the user types; debounces 250 ms before
    /// hitting the network. Single-character queries are ignored to avoid
    /// flooding Algolia with mostly-useless prefix matches.
    func update(query newQuery: String) {
        let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != query else { return }
        query = trimmed
        pendingTask?.cancel()
        if trimmed.count < 2 {
            results = []
            errorMessage = nil
            totalHits = 0
            isLoading = false
            return
        }
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.runSearch(reset: true)
        }
    }

    /// Re-run the current query (used by pull-to-refresh in search results).
    func refresh() async {
        guard query.count >= 2 else { return }
        await runSearch(reset: true)
    }

    func loadMoreIfNeeded(current: HNItem) async {
        guard hasMore, !isLoading,
              let index = results.firstIndex(of: current),
              index >= results.count - 5 else { return }
        await runSearch(reset: false)
    }

    private func rerunCurrentQuery() {
        guard !query.isEmpty else { return }
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            await self?.runSearch(reset: true)
        }
    }

    private func runSearch(reset: Bool) async {
        if reset { currentPage = 0 }
        let pageToFetch = reset ? 0 : currentPage + 1
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await HNSearchService.shared.search(
                query: query,
                sort: sort,
                page: pageToFetch
            )
            if reset {
                results = page.stories
            } else {
                results.append(contentsOf: page.stories)
            }
            currentPage = page.page
            hasMore = page.hasMore
            totalHits = page.totalHits
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
}
