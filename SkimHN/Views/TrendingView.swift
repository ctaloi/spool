import SwiftUI
import SwiftData

/// Stories climbing fastest in the last 24h, computed from local
/// `ScoreSnapshot` history. The snapshots accumulate as the user browses
/// normal feeds — so a fresh install starts empty and fills in as they
/// use the app. Honest, no background polling.
struct TrendingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthViewModel
    @Query private var savedStories: [SavedStory]
    @Query private var readStories: [ReadStory]

    @State private var entries: [TrendingEntry] = []
    @State private var items: [HNItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var savedIDs: Set<Int> { Set(savedStories.map(\.id)) }
    private var readIDs: Set<Int> { Set(readStories.map(\.id)) }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Trending")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
                .navigationDestination(for: HNItem.self) { story in
                    StoryDetailView(story: story)
                }
                .refreshable { await load() }
                .task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage, items.isEmpty {
            ContentUnavailableView(
                "Couldn't compute trends",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
        } else if items.isEmpty && isLoading {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty {
            ContentUnavailableView {
                Label("Not enough data yet", systemImage: "chart.line.uptrend.xyaxis")
            } description: {
                Text("Browse a feed a couple of times and come back — Trending uses score changes between your visits to find stories that are climbing fast.")
                    .multilineTextAlignment(.center)
            }
        } else {
            List {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, story in
                    NavigationLink(value: story) {
                        StoryRowView(
                            rank: index + 1,
                            story: story,
                            context: contextLine(for: story),
                            isRead: readIDs.contains(story.id),
                            isSaved: savedIDs.contains(story.id)
                        )
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func contextLine(for story: HNItem) -> String? {
        guard let entry = entries.first(where: { $0.itemID == story.id }) else { return nil }
        let rate = Int(entry.pointsPerHour.rounded())
        return "+\(rate) pts/h"
    }

    private func load() async {
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
            // Preserve the velocity-ranked order rather than HNAPI's.
            // Use `uniquingKeysWith:` instead of `uniqueKeysWithValues:`
            // so a hypothetical duplicate id from HNAPI can't crash us.
            let byID = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            self.items = computed.compactMap { byID[$0.itemID] }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
