import SwiftUI
import SwiftData

/// The user's Read Later queue. Same chrome as SavedStoriesView, but
/// the destructive swipe is framed as "clear from queue" rather than
/// "remove from archive". Tapping a row promotes the natural "read it"
/// path — opening the detail screen also marks it as read elsewhere.
struct ReadLaterView: View {
    @Query(sort: \ReadLaterStory.queuedAt, order: .reverse) private var queued: [ReadLaterStory]
    @Query private var readStories: [ReadStory]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var readIDs: Set<Int> { Set(readStories.map(\.id)) }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Read Later")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
                .navigationDestination(for: HNItem.self) { story in
                    StoryDetailView(story: story)
                }
                .sensoryFeedback(.success, trigger: queued.count)
        }
    }

    @ViewBuilder
    private var content: some View {
        if queued.isEmpty {
            ContentUnavailableView(
                "Empty Queue",
                systemImage: "tray",
                description: Text("Swipe a story and tap Read Later to queue it up.")
            )
        } else {
            List {
                ForEach(Array(queued.enumerated()), id: \.element.id) { _, item in
                    NavigationLink(value: item.asHNItem) {
                        StoryRowView(
                            rank: nil,
                            story: item.asHNItem,
                            context: queuedContext(for: item),
                            isRead: readIDs.contains(item.id),
                            isSaved: false
                        )
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            modelContext.delete(item)
                        } label: {
                            Label("Clear", systemImage: "tray.and.arrow.up")
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func queuedContext(for item: ReadLaterStory) -> String {
        "Queued \(item.queuedAt.formatted(.relative(presentation: .named)))"
    }
}
