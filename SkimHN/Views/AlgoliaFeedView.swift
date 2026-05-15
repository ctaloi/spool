import SwiftUI
import SwiftData

/// Typed navigation destination so `NavigationLink(value:)` can be used
/// to push a domain feed or best-of feed from any row chip / sidebar
/// entry without each call site having to construct the full view.
enum AlgoliaFeedDestination: Hashable {
    case domain(String)
    case bestOf(BestOfWindow)

    @ViewBuilder
    var view: some View {
        switch self {
        case .domain(let host):
            AlgoliaFeedView(
                kind: .domain(host),
                navigationTitle: host,
                navigationSubtitle: "Stories from \(host)",
                navigationSystemImage: "globe"
            )
        case .bestOf(let window):
            AlgoliaFeedView(
                kind: .bestOf(window),
                navigationTitle: "Best of \(window.title)",
                navigationSubtitle: nil,
                navigationSystemImage: window.icon
            )
        }
    }
}

/// Generic destination view for Algolia-backed feeds — domain feeds and
/// best-of windows both push this. Renders the same story row list as
/// the main feed, with its own pagination + refresh, and a title that
/// matches the kind.
struct AlgoliaFeedView: View {
    let kind: AlgoliaFeedKind
    let navigationTitle: String
    let navigationSubtitle: String?
    let navigationSystemImage: String?

    @StateObject private var feed = AlgoliaFeedViewModel()
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.modelContext) private var modelContext
    @Query private var savedStories: [SavedStory]
    @Query private var readStories: [ReadStory]
    @Query private var readLaterStories: [ReadLaterStory]

    private var savedIDs: Set<Int> { Set(savedStories.map(\.id)) }
    private var readIDs: Set<Int> { Set(readStories.map(\.id)) }
    private var readLaterIDs: Set<Int> { Set(readLaterStories.map(\.id)) }

    init(
        kind: AlgoliaFeedKind,
        navigationTitle: String,
        navigationSubtitle: String? = nil,
        navigationSystemImage: String? = nil
    ) {
        self.kind = kind
        self.navigationTitle = navigationTitle
        self.navigationSubtitle = navigationSubtitle
        self.navigationSystemImage = navigationSystemImage
    }

    var body: some View {
        content
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.large)
            // Register the detail destination at the root so taps work
            // regardless of which conditional content branch (results,
            // loading, empty, error) is currently rendered.
            .navigationDestination(for: HNItem.self) { story in
                StoryDetailView(story: story)
            }
            .toolbarTitleMenu {
                if let navigationSubtitle {
                    Label(navigationSubtitle, systemImage: navigationSystemImage ?? "info.circle")
                }
            }
            .refreshable { await feed.refresh() }
            .task {
                feed.kind = kind
                await feed.loadInitialIfNeeded()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let message = feed.errorMessage, feed.results.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") {
                    Task { await feed.refresh() }
                }
                .buttonStyle(.bordered)
            }
        } else if feed.results.isEmpty && feed.isLoading {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if feed.results.isEmpty {
            ContentUnavailableView(
                "Nothing here",
                systemImage: "tray",
                description: Text("No stories matched this view.")
            )
        } else {
            List {
                ForEach(Array(feed.results.enumerated()), id: \.element.id) { index, story in
                    NavigationLink(value: story) {
                        StoryRowView(
                            rank: index + 1,
                            story: story,
                            isRead: readIDs.contains(story.id),
                            isSaved: savedIDs.contains(story.id)
                        )
                    }
                    .task { await feed.loadMoreIfNeeded(current: story) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            toggleSaved(story)
                        } label: {
                            Label(savedIDs.contains(story.id) ? "Unsave" : "Save", systemImage: "bookmark.fill")
                        }
                        .tint(Theme.accent)

                        Button {
                            toggleReadLater(story)
                        } label: {
                            Label(
                                readLaterIDs.contains(story.id) ? "Dequeue" : "Read Later",
                                systemImage: readLaterIDs.contains(story.id) ? "tray.and.arrow.up" : "tray.and.arrow.down"
                            )
                        }
                        .tint(.purple)
                    }
                }

                if feed.isLoading && !feed.results.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView().tint(Theme.accent)
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
    }

    private func toggleSaved(_ story: HNItem) {
        if let existing = savedStories.first(where: { $0.id == story.id }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(SavedStory(
                id: story.id,
                title: story.title ?? "(untitled)",
                urlString: story.url,
                author: story.by,
                score: story.score,
                descendants: story.descendants
            ))
        }
    }

    private func toggleReadLater(_ story: HNItem) {
        if let existing = readLaterStories.first(where: { $0.id == story.id }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(ReadLaterStory(
                id: story.id,
                title: story.title ?? "(untitled)",
                urlString: story.url,
                author: story.by,
                score: story.score,
                descendants: story.descendants
            ))
        }
    }
}
