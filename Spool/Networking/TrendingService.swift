import Foundation
import SwiftData

/// Stories the user has seen, ranked by score velocity (points gained
/// per hour) computed from local `ScoreSnapshot` history. Pure on-device
/// — no extra network polling. Snapshots accumulate as the user browses
/// normal feeds; the trending feed surfaces what's been climbing fastest
/// in the last 24 hours.
struct TrendingEntry {
    let itemID: Int
    let pointsGained: Int
    let hoursElapsed: Double
    var pointsPerHour: Double {
        guard hoursElapsed > 0 else { return Double(pointsGained) }
        return Double(pointsGained) / hoursElapsed
    }
}

enum TrendingService {
    /// Record a score snapshot for each freshly fetched story. Cheap
    /// SwiftData insert; the view layer calls this after every successful
    /// reload of the standard feeds.
    static func recordSnapshots(
        for stories: [HNItem],
        in modelContext: ModelContext
    ) {
        let now = Date.now
        for story in stories where (story.score ?? 0) > 0 {
            modelContext.insert(
                ScoreSnapshot(
                    itemID: story.id,
                    score: story.score ?? 0,
                    capturedAt: now
                )
            )
        }
        try? modelContext.save()
    }

    /// Compute the top trending items from the snapshot table.
    /// Looks at the last 24 hours, requires ≥ 2 snapshots per item,
    /// returns top 30 by points-per-hour. Caller fetches the live items
    /// via HNAPI to get current state for rendering.
    static func computeTrending(
        modelContext: ModelContext,
        windowHours: Double = 24,
        topN: Int = 30
    ) -> [TrendingEntry] {
        let cutoff = Date.now.addingTimeInterval(-windowHours * 3600)
        let descriptor = FetchDescriptor<ScoreSnapshot>(
            predicate: #Predicate { $0.capturedAt >= cutoff },
            sortBy: [SortDescriptor(\.capturedAt)]
        )
        guard let snapshots = try? modelContext.fetch(descriptor) else { return [] }

        // Group by itemID. Each item needs ≥ 2 snapshots to compute a
        // velocity (delta-score / delta-time).
        var byItem: [Int: [ScoreSnapshot]] = [:]
        for snap in snapshots {
            byItem[snap.itemID, default: []].append(snap)
        }
        let entries: [TrendingEntry] = byItem.compactMap { (id, snaps) in
            guard snaps.count >= 2,
                  let first = snaps.first,
                  let last = snaps.last,
                  last.score > first.score else { return nil }
            let hours = last.capturedAt.timeIntervalSince(first.capturedAt) / 3600
            return TrendingEntry(
                itemID: id,
                pointsGained: last.score - first.score,
                hoursElapsed: max(hours, 0.05) // floor at 3 minutes
            )
        }
        return entries
            .sorted { $0.pointsPerHour > $1.pointsPerHour }
            .prefix(topN)
            .map { $0 }
    }

    /// Drops snapshots older than the window so the table doesn't grow
    /// indefinitely. Called opportunistically when the Trending feed is
    /// opened.
    static func pruneOldSnapshots(
        in modelContext: ModelContext,
        olderThanHours: Double = 48
    ) {
        let cutoff = Date.now.addingTimeInterval(-olderThanHours * 3600)
        let descriptor = FetchDescriptor<ScoreSnapshot>(
            predicate: #Predicate { $0.capturedAt < cutoff }
        )
        guard let stale = try? modelContext.fetch(descriptor) else { return }
        for snap in stale {
            modelContext.delete(snap)
        }
        try? modelContext.save()
    }
}
