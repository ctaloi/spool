import Foundation

/// Powers any Algolia-backed list: search, domain feed, best-of windows.
/// Same pagination + debounce + error model regardless of source — the
/// only thing that changes is the `kind`. Replaces the old
/// `SearchViewModel`; the typealias preserves the old name for views
/// that still talk to it.
@MainActor
final class AlgoliaFeedViewModel: ObservableObject {
    @Published private(set) var results: [HNItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var totalHits: Int = 0
    /// Used only by the search flavor (the search field listens to this
    /// for the sort scope picker). Setting it triggers a re-run of the
    /// current query.
    @Published var sort: HNSearchSort = .relevance {
        didSet { rerunCurrentSearch() }
    }

    /// The active feed kind. For search, `update(query:)` mutates it
    /// indirectly via the published query string; for domain / best-of
    /// the destination view sets it once on `.task`. Setting it to a
    /// new value clears the prior fetch state synchronously — without
    /// this the view briefly shows the previous window's results, then
    /// either flickers to "Nothing here" if the new fetch is empty or
    /// stays stuck on a stale "Loading…" if the prior in-flight fetch
    /// gets cancelled before its catch path can reset state.
    @Published var kind: AlgoliaFeedKind {
        didSet {
            guard oldValue != kind else { return }
            results = []
            errorMessage = nil
            hasMore = false
            currentPage = 0
            totalHits = 0
        }
    }
    private(set) var query: String = ""
    private var currentPage: Int = 0
    /// Whether the most recent page reported more pages available.
    /// Exposed so the view can render an auto-pagination sentinel
    /// even before `isLoading` flips for the next batch.
    @Published private(set) var hasMore: Bool = false
    private var pendingTask: Task<Void, Never>?

    init(kind: AlgoliaFeedKind = .search(query: "", sort: .relevance)) {
        self.kind = kind
        if case .search(let q, let s) = kind {
            self.query = q
            self.sort = s
        }
    }

    /// Search-flavor only: debounced query update from the search field.
    func update(query newQuery: String) {
        let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != query else { return }
        query = trimmed
        kind = .search(query: trimmed, sort: sort)
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
            await self?.run(reset: true)
        }
    }

    func refresh() async {
        switch kind {
        case .search where query.count < 2: return
        default: break
        }
        await run(reset: true)
    }

    func loadMoreIfNeeded(current: HNItem) async {
        guard hasMore, !isLoading,
              let index = results.firstIndex(of: current),
              index >= results.count - 5 else { return }
        await run(reset: false)
    }

    /// Unconditional next-page load. Used by the bottom-of-list
    /// auto-pagination spinner — its visibility itself signals
    /// "fetch more", and we want to chain through filtered batches
    /// that pass nothing through the row gate.
    func loadMore() async {
        guard hasMore, !isLoading else { return }
        await run(reset: false)
    }

    /// Fire an initial load for domain / best-of feeds where the kind is
    /// fixed and there's no debounce.
    func loadInitialIfNeeded() async {
        guard results.isEmpty, !isLoading else { return }
        await run(reset: true)
    }

    private func rerunCurrentSearch() {
        guard case .search = kind, !query.isEmpty else { return }
        kind = .search(query: query, sort: sort)
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            await self?.run(reset: true)
        }
    }

    private func run(reset: Bool) async {
        if reset { currentPage = 0 }
        let pageToFetch = reset ? 0 : currentPage + 1
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await HNSearchService.shared.fetch(kind, page: pageToFetch)
            if reset {
                results = page.stories
            } else {
                results.append(contentsOf: page.stories)
            }
            currentPage = page.page
            hasMore = page.hasMore
            totalHits = page.totalHits
        } catch {
            if Self.isCancellation(error) { return }
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

/// Back-compat alias so the existing `@StateObject private var search =
/// SearchViewModel()` reference in `StoryListView` keeps working without
/// a rename pass.
typealias SearchViewModel = AlgoliaFeedViewModel
