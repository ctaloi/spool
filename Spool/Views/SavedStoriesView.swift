import SwiftUI
import SwiftData

struct SavedStoriesView: View {
    @Query(sort: \SavedStory.savedAt, order: .reverse) private var saved: [SavedStory]
    @Query private var readStories: [ReadStory]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var readIDs: Set<Int> { Set(readStories.map(\.id)) }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Saved")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
                .navigationDestination(for: HNItem.self) { story in
                    StoryDetailView(story: story)
                }
                .sensoryFeedback(.success, trigger: saved.count)
        }
    }

    @ViewBuilder
    private var content: some View {
        if saved.isEmpty {
            ContentUnavailableView(
                "No Saved Stories",
                systemImage: "bookmark",
                description: Text("Swipe right on a story in the feed to save it for later.")
            )
        } else {
            List {
                ForEach(Array(saved.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: item.asHNItem) {
                        StoryRowView(
                            story: item.asHNItem,
                            context: savedContext(for: item),
                            isRead: readIDs.contains(item.id),
                            isSaved: true
                        )
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            modelContext.delete(item)
                        } label: {
                            Label("Remove", systemImage: "bookmark.slash")
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func savedContext(for item: SavedStory) -> String {
        "Saved \(item.savedAt.formatted(.relative(presentation: .named)))"
    }
}
