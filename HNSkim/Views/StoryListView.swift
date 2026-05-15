import SwiftUI
import SwiftData

struct StoryListView: View {
    @StateObject private var viewModel = StoryListViewModel()
    @StateObject private var search = SearchViewModel()
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Query private var savedStories: [SavedStory]
    @Query private var readStories: [ReadStory]
    @State private var showLogin = false
    @State private var showSubmit = false
    @State private var showSaved = false
    @State private var searchText = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .content
    @State private var selectedStory: HNItem?
    /// True while the user is at the top of the story list — drives the
    /// scroll-aware hamburger button visibility.
    @State private var listAtTop: Bool = true
    @FocusState private var searchFieldFocused: Bool

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var savedIDs: Set<Int> { Set(savedStories.map(\.id)) }
    private var readIDs: Set<Int> { Set(readStories.map(\.id)) }
    private var usesCompactNavigation: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility,
            preferredCompactColumn: $preferredCompactColumn
        ) {
            AppSidebar(
                viewModel: viewModel,
                onSignIn: { showLogin = true },
                onSignOut: { Task { await auth.logout() } },
                onSubmit: { showSubmit = true },
                onSaved: { showSaved = true },
                onDismiss: usesCompactNavigation ? {
                    withAnimation(.easeOut(duration: 0.22)) {
                        preferredCompactColumn = .content
                        columnVisibility = .automatic
                    }
                } : nil
            )
            .environmentObject(auth)
        } content: {
            listContent
        } detail: {
            if let story = selectedStory {
                StoryDetailView(story: story)
                    .id(story.id)
            } else {
                ContentUnavailableView(
                    "Pick a story",
                    systemImage: "doc.text",
                    description: Text("Stories you tap will open here.")
                )
            }
        }
        .tint(Theme.accent)
        .onChange(of: viewModel.feed) { _, _ in
            // Switching feed in the sidebar should bring the content
            // column forward in compact mode.
            selectedStory = nil
            preferredCompactColumn = .content
        }
        .sheet(isPresented: $showLogin) {
            LoginView().environmentObject(auth)
        }
        .sheet(isPresented: $showSubmit) {
            SubmitView().environmentObject(auth)
        }
        .sheet(isPresented: $showSaved) {
            SavedStoriesView().environmentObject(auth)
        }
    }

    // MARK: - Content column

    private var listContent: some View {
        content
            // Title is purely for accessibility / back-button label now —
            // the visible title lives in the in-list hero header at the
            // top of scroll, and reappears as a small inline chip in the
            // toolbar (`titleChip`) once the user scrolls past the hero.
            .navigationTitle(isSearching ? "Search" : feedSectionTitle)
            .navigationBarTitleDisplayMode(.inline)
            // Hide the system back-to-sidebar arrow on compact width —
            // edge-swipe and the hero hamburger handle sidebar access.
            .navigationBarBackButtonHidden(usesCompactNavigation)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if usesCompactNavigation && !listAtTop && !isSearching {
                        titleChip
                    } else {
                        // Suppress the centered system title — the hero
                        // owns the look while the user is at the top.
                        Color.clear.frame(width: 1, height: 1)
                    }
                }
            }
            .refreshable {
                if isSearching {
                    await search.refresh()
                } else {
                    await viewModel.reload()
                }
            }
            .task {
                if viewModel.stories.isEmpty {
                    await viewModel.reload()
                }
            }
            .onChange(of: searchText) { _, new in
                search.update(query: new)
            }
            .sensoryFeedback(.success, trigger: savedStories.count)
    }

    /// Single shared list so the hero + inline search field stay visible
    /// in both the feed and search states (and during their error /
    /// loading variants).
    @ViewBuilder
    private var content: some View {
        List(selection: $selectedStory) {
            heroHeader
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 6, trailing: 18))
                .selectionDisabled()

            inlineSearchField
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 8, trailing: 18))
                .selectionDisabled()

            if isSearching {
                searchRows
            } else {
                feedRows
            }
        }
        .listStyle(.plain)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollAwareTopState(isAtTop: $listAtTop)
        .animation(.easeInOut(duration: 0.18), value: isSearching)
    }

    @ViewBuilder
    private var feedRows: some View {
        feedContextHeader
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 2, leading: 18, bottom: 10, trailing: 18))
            .selectionDisabled()

        if let message = viewModel.errorMessage, viewModel.stories.isEmpty {
            statusRow {
                ContentUnavailableView {
                    Label("Couldn't load stories", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") {
                        Task { await viewModel.reload() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else if viewModel.stories.isEmpty && viewModel.isLoading {
            statusRow {
                LoadingStateView(text: "Loading \(viewModel.feed.title.lowercased())…")
            }
        } else {
            ForEach(Array(viewModel.stories.enumerated()), id: \.element.id) { index, story in
                storyRow(rank: index + 1, story: story)
                    .task { await viewModel.loadMoreIfNeeded(current: story) }
            }

            if viewModel.stories.count < viewModel.totalAvailable {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
    }

    /// The big in-list header at top of scroll. Hamburger on the left
    /// (iPhone only — iPad's sidebar is permanent), feed section icon
    /// and a large, thin-weight title on the right. The title is a Menu
    /// trigger for switching feeds.
    private var heroHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            if usesCompactNavigation {
                Button {
                    withAnimation(.easeOut(duration: 0.22)) {
                        columnVisibility = .all
                        preferredCompactColumn = .sidebar
                    }
                } label: {
                    Image(systemName: "sidebar.leading")
                        .font(.title3.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Show Menu")
            }

            Spacer(minLength: 8)

            Menu {
                ForEach(HNStoryFeed.allCases) { feed in
                    Button {
                        viewModel.feed = feed
                    } label: {
                        Label(
                            feed.navigationTitle,
                            systemImage: feed == viewModel.feed ? "checkmark" : feed.icon
                        )
                    }
                }
            } label: {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Image(systemName: viewModel.feed.icon)
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Theme.accent)
                    Text(feedSectionTitle)
                        .font(.system(size: 34, weight: .thin, design: .default))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentTransition(.interpolate)
                .animation(.easeInOut(duration: 0.2), value: viewModel.feed)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("Switch feed")
            .accessibilityValue(feedSectionTitle)
        }
        .padding(.vertical, 4)
    }

    /// Compact section indicator that appears in the inline title bar
    /// once the hero has scrolled out of view. Same icon + name pairing
    /// as the hero, scaled down, so the user always knows what they're
    /// reading.
    private var titleChip: some View {
        HStack(spacing: 6) {
            Image(systemName: viewModel.feed.icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text(feedSectionTitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Thin stats row between the search drawer and the first story.
    /// Feed name lives in the hero now, so this is just
    /// "30 stories · Updated 2m ago" — quiet, scrolls away with the list.
    private var feedContextHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("\(viewModel.stories.count) stories")
                .monospacedDigit()
            if let date = viewModel.lastReloadedAt {
                Text(verbatim: "·")
                    .foregroundStyle(.tertiary)
                Text("Updated \(date, format: .relative(presentation: .named))")
            }
            Spacer(minLength: 0)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var feedSectionTitle: String {
        switch viewModel.feed {
        case .ask: return "Ask HN"
        case .show: return "Show HN"
        case .job: return "Jobs"
        default: return "\(viewModel.feed.title) Stories"
        }
    }

    @ViewBuilder
    private func storyRow(rank: Int, story: HNItem) -> some View {
        StoryRowView(
            rank: rank,
            story: story,
            isRead: readIDs.contains(story.id),
            isSaved: savedIDs.contains(story.id)
        )
        .tag(story)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                toggleSaved(story)
            } label: {
                Label(savedIDs.contains(story.id) ? "Unsave" : "Save", systemImage: "bookmark.fill")
            }
            .tint(Theme.accent)

            Button {
                viewModel.share(story)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(.blue)
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

    @ViewBuilder
    private var searchRows: some View {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Scope picker — sits where the feed-context strip would be, so
        // the visual rhythm matches the feed view.
        Picker("Sort", selection: $search.sort) {
            Text("Relevance").tag(HNSearchSort.relevance)
            Text("Newest").tag(HNSearchSort.newest)
        }
        .pickerStyle(.segmented)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 10, trailing: 18))
        .selectionDisabled()

        if let message = search.errorMessage, search.results.isEmpty {
            statusRow {
                ContentUnavailableView {
                    Label("Search failed", systemImage: "magnifyingglass")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") {
                        Task { await search.refresh() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else if search.results.isEmpty && search.isLoading {
            statusRow {
                LoadingStateView(text: "Searching…")
            }
        } else if trimmedSearchText.count < 2 {
            statusRow {
                ContentUnavailableView(
                    "Keep typing",
                    systemImage: "magnifyingglass",
                    description: Text("Search starts with two characters.")
                )
            }
        } else if search.results.isEmpty {
            statusRow {
                ContentUnavailableView.search(text: searchText)
            }
        } else {
            searchHeader
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 8, trailing: 18))
                .selectionDisabled()

            ForEach(Array(search.results.enumerated()), id: \.element.id) { index, story in
                storyRow(rank: index + 1, story: story)
                    .task { await search.loadMoreIfNeeded(current: story) }
            }

            if search.isLoading && !search.results.isEmpty {
                HStack {
                    Spacer()
                    ProgressView().tint(Theme.accent)
                    Spacer()
                }
                .padding(.vertical, 12)
                .listRowSeparator(.hidden)
            }
        }
    }

    private var searchHeader: some View {
        Text("\(search.totalHits.formatted()) results")
            .font(Theme.Typography.subheadlineStrong)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textCase(nil)
    }

    /// Wraps a full-bleed status view (`ContentUnavailableView` / loading)
    /// in a single list row so it sits below the hero + search field
    /// instead of replacing the whole screen.
    @ViewBuilder
    private func statusRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18))
            .selectionDisabled()
    }

    /// Inline glass search field that lives just below the hero. Replaces
    /// the system `.searchable` drawer so the search affordance sits
    /// underneath the title rather than between the title and the
    /// toolbar. Scrolls away with the rest of the header rows.
    private var inlineSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)

            TextField("Search Hacker News", text: $searchText)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .focused($searchFieldFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }

            if searchFieldFocused {
                Button("Cancel") {
                    searchText = ""
                    searchFieldFocused = false
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassEffect(.regular, in: Capsule(style: .continuous))
        .animation(.easeInOut(duration: 0.18), value: searchFieldFocused)
        .animation(.easeInOut(duration: 0.18), value: searchText.isEmpty)
    }
}

// MARK: - Loading state

private struct LoadingStateView: View {
    let text: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
            Text(text)
                .font(Theme.Typography.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Scroll-aware "at top" detection

/// Reports whether the attached scrolling view is at (or very near) its
/// top. Used to hide the hamburger toolbar item while reading.
private struct ScrollTopStateModifier: ViewModifier {
    @Binding var isAtTop: Bool

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y <= geometry.contentInsets.top + 4
        } action: { _, newValue in
            if newValue != isAtTop {
                withAnimation(.easeOut(duration: 0.18)) {
                    isAtTop = newValue
                }
            }
        }
    }
}

private extension View {
    func scrollAwareTopState(isAtTop: Binding<Bool>) -> some View {
        modifier(ScrollTopStateModifier(isAtTop: isAtTop))
    }
}

#Preview {
    StoryListView()
        .modelContainer(for: [SavedStory.self, ReadStory.self], inMemory: true)
        .environmentObject(AuthViewModel())
}
