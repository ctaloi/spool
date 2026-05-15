import Foundation
import SwiftData

/// Drives the inline Trending view in the main list. Computes velocity
/// entries from local snapshots, fetches the live items via HNAPI, and
/// preserves the ranked order.
@MainActor
final class TrendingFeedViewModel: ObservableObject {
    @Published private(set) var entries: [TrendingEntry] = []
    @Published private(set) var items: [HNItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    func load(modelContext: ModelContext) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        TrendingService.pruneOldSnapshots(in: modelContext)
        let computed = TrendingService.computeTrending(modelContext: modelContext)
        self.entries = computed
        guard !computed.isEmpty else {
            self.items = []
            return
        }
        do {
            let fetched = try await HNAPI.shared.items(ids: computed.map(\.itemID))
            // Preserve velocity-ranked order rather than HNAPI's.
            let byID = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            self.items = computed.compactMap { byID[$0.itemID] }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func contextLine(for story: HNItem) -> String? {
        guard let entry = entries.first(where: { $0.itemID == story.id }) else { return nil }
        let rate = Int(entry.pointsPerHour.rounded())
        return "+\(rate) pts/h"
    }
}
