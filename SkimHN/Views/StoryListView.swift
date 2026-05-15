import SwiftUI
import SwiftData

struct StoryListView: View {
    @StateObject private var viewModel = StoryListViewModel()
    @StateObject private var search = SearchViewModel()
    @StateObject private var browse = AlgoliaFeedViewModel()
    @StateObject private var trending = TrendingFeedViewModel()
    @StateObject private var digest = DigestViewModel()
    @StateObject private var following = FollowingFeedViewModel()
    @Query private var followedUsers: [FollowedUser]
    @AppStorage(SettingsKeys.lastOpenedAt) private var lastOpenedAt: Double = 0
    @AppStorage(SettingsKeys.lastDigestDismissedDay) private var lastDigestDismissedDay: Int = 0
    @State private var showDigest: Bool = false
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedStory.savedAt, order: .reverse) private var savedStories: [SavedStory]
    @Query private var readStories: [ReadStory]
    @Query(sort: \ReadLaterStory.queuedAt, order: .reverse) private var readLaterStories: [ReadLaterStory]
    @State private var showLogin = false
    @State private var showSubmit = false
    /// Drives what the main list renders. Updated by the title-bar
    /// selector and the sidebar. Defaults to Top Stories on launch.
    @State private var feedSource: MainFeedSource = .category(.top)
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
    private var readLaterIDs: Set<Int> { Set(readLaterStories.map(\.id)) }
    private var usesCompactNavigation: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility,
            preferredCompactColumn: $preferredCompactColumn
        ) {
            AppSidebar(
                activeSource: feedSource,
                onSignIn: { showLogin = true },
                onSignOut: { Task { await auth.logout() } },
                onSubmit: { showSubmit = true },
                onSelect: { source in switchSource(to: source) },
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
                DetailPlaceholderView()
            }
        }
        // `.balanced` keeps all three columns visible side-by-side on
        // iPad (regular size class) so the user gets a true three-pane
        // sidebar / list / detail layout. iPhone (compact) still
        // collapses to a single column with the standard stacking
        // behavior, driven by `preferredCompactColumn`.
        .navigationSplitViewStyle(.balanced)
        .tint(Theme.accent)
        .onChange(of: feedSource) { _, new in
            // Whenever the source changes, clear the detail selection
            // and bring the content column forward in compact mode.
            selectedStory = nil
            preferredCompactColumn = .content
            // Keep the category view model in lock-step so reload-on-feed-
            // change continues to work and snapshots still get recorded.
            if case .category(let feed) = new, viewModel.feed != feed {
                viewModel.feed = feed
            }
        }
        .sheet(isPresented: $showLogin) {
            LoginView().environmentObject(auth)
        }
        .sheet(isPresented: $showSubmit) {
            SubmitView().environmentObject(auth)
        }
    }

    /// Reveal the sidebar from the content column. Uses a snappy spring
    /// so the on-release transition feels responsive rather than the
    /// slower ease-out we were doing before. NavigationSplitView in
    /// compact mode doesn't expose state for a truly interactive (drag-
    /// tracking) reveal, so on-release with a spring is the smoothest
    /// approximation.
    private func presentSidebar() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            columnVisibility = .all
            preferredCompactColumn = .sidebar
        }
    }

    /// Leading-edge rightward drag reveals the sidebar. Triggers on
    /// release once the user has clearly committed to the gesture
    /// (started near the leading edge, moved right by ≥50pt, mostly
    /// horizontal). `simultaneousGesture` so the list's vertical scroll
    /// keeps working.
    private var leadingEdgeSwipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard usesCompactNavigation else { return }
                let startedAtLeadingEdge = value.startLocation.x < 50
                let movedRightward = value.translation.width > 50
                let mostlyHorizontal = abs(value.translation.width) > abs(value.translation.height)
                if startedAtLeadingEdge && movedRightward && mostlyHorizontal {
                    presentSidebar()
                }
            }
    }

    /// Centralized switch — also dismisses the compact sidebar so the
    /// content column comes forward immediately after a sidebar tap.
    private func switchSource(to source: MainFeedSource) {
        feedSource = source
        if usesCompactNavigation {
            withAnimation(.easeOut(duration: 0.22)) {
                preferredCompactColumn = .content
                columnVisibility = .automatic
            }
        }
    }

    /// Fires whenever `feedSource` changes. Each source has its own
    /// loader; the category one is intentionally a no-op because the
    /// `.onChange(of: feedSource)` above forwards into
    /// `viewModel.feed = feed`, which triggers `viewModel.reload()` via
    /// its `didSet`.
    private func loadCurrentSource() async {
        switch feedSource {
        case .category:
            break
        case .trending:
            await trending.load(modelContext: modelContext)
        case .bestOf(let window):
            browse.kind = .bestOf(window)
            // Force a reload — the user may be returning to the same
            // window after viewing another source.
            await browse.refresh()
        case .saved, .readLater:
            // SwiftData @Query keeps these live; nothing to fetch.
            break
        case .following:
            await following.load(usernames: followedUsers.map(\.username))
        }
    }

    /// Hook fired after the Top feed first loads with stories. If the
    /// user hasn't seen a digest today, generate one from the top of
    /// the feed and reveal the card.
    private func maybeShowDigestIfNeeded() {
        guard feedSource == .category(.top) else { return }
        guard digest.canRun else { return }
        guard !viewModel.stories.isEmpty else { return }

        let now = Date.now
        let todayDay = Calendar.current.ordinality(of: .day, in: .year, for: now) ?? 0
        let lastOpenedDate = lastOpenedAt > 0
            ? Date(timeIntervalSince1970: lastOpenedAt)
            : now.addingTimeInterval(-86_400)
        let lastOpenedDay = Calendar.current.ordinality(of: .day, in: .year, for: lastOpenedDate) ?? todayDay

        // Already dismissed today → leave them alone.
        if lastDigestDismissedDay == todayDay { return }
        // First launch of a new day → eligible.
        guard todayDay != lastOpenedDay else { return }

        digest.generate(stories: viewModel.stories)
        withAnimation(.easeOut(duration: 0.35)) {
            showDigest = true
        }
        lastOpenedAt = now.timeIntervalSince1970
    }

    private func dismissDigest() {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 0
        lastDigestDismissedDay = day
        withAnimation(.easeInOut(duration: 0.3)) {
            showDigest = false
        }
        digest.cancel()
    }

    /// Pull-to-refresh dispatch.
    private func refreshCurrentSource() async {
        if isSearching && feedSource.supportsSearch {
            await search.refresh()
            return
        }
        switch feedSource {
        case .category:
            await viewModel.reload()
        case .trending:
            await trending.load(modelContext: modelContext)
        case .bestOf:
            await browse.refresh()
        case .saved, .readLater:
            // SwiftData @Query updates automatically.
            break
        case .following:
            await following.load(usernames: followedUsers.map(\.username))
        }
    }

    // MARK: - Content column

    private var listContent: some View {
        content
            // Title is purely for accessibility / back-button label now —
            // the visible title lives in the in-list hero header at the
            // top of scroll, and reappears as a small inline chip in the
            // toolbar (`titleChip`) once the user scrolls past the hero.
            .navigationTitle(isSearching ? "Search" : feedSource.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            // Hide the system back-to-sidebar arrow on compact width —
            // edge-swipe and the hero hamburger handle sidebar access.
            .navigationBarBackButtonHidden(usesCompactNavigation)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if !isSearching && !listAtTop {
                        inlineFeedSelector
                            .transition(.opacity.animation(.easeInOut(duration: 0.28)))
                    } else {
                        Color.clear
                            .frame(width: 1, height: 1)
                            .transition(.opacity.animation(.easeInOut(duration: 0.28)))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.28), value: listAtTop)
            // Hide the navbar entirely while the hero is on-screen so
            // the hero touches the status bar with no chrome in between.
            // The scroll observer's hysteresis (in `ScrollTopStateModifier`)
            // keeps this stable when the navbar's frame appears/disappears.
            .toolbar(
                (listAtTop && !isSearching) ? .hidden : .visible,
                for: .navigationBar
            )
            .refreshable {
                await refreshCurrentSource()
            }
            .task {
                if viewModel.stories.isEmpty {
                    await viewModel.reload()
                }
            }
            // Whenever the source switches, fire the appropriate loader.
            // The category source loads via `viewModel.feed.didSet` (set
            // by the onChange below). The others load explicitly here.
            .task(id: feedSource) {
                await loadCurrentSource()
            }
            // Single place where snapshots get recorded. Fires for the
            // initial load, every pull-to-refresh, AND every sidebar feed
            // switch (which reloads via `viewModel.feed.didSet`).
            .onChange(of: viewModel.lastReloadedAt) { _, _ in
                TrendingService.recordSnapshots(for: viewModel.stories, in: modelContext)
                maybeShowDigestIfNeeded()
            }
            .onChange(of: searchText) { _, new in
                search.update(query: new)
            }
            .sensoryFeedback(.success, trigger: savedStories.count)
        .sensoryFeedback(.selection, trigger: feedSource)
    }

    /// Single shared list so the hero stays visible in every source
    /// (categories, search, trending, best-of, library) and during
    /// their error / loading variants.
    @ViewBuilder
    private var content: some View {
        List(selection: $selectedStory) {
            heroHeader
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 6, trailing: 18))
                .selectionDisabled()

            if feedSource.supportsSearch {
                inlineSearchField
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 8, trailing: 18))
                    .selectionDisabled()
            }

            if isSearching && feedSource.supportsSearch {
                searchRows
            } else {
                switch feedSource {
                case .category: feedRows
                case .trending: trendingRows
                case .bestOf: bestOfRows
                case .saved: savedRows
                case .readLater: readLaterRows
                case .following: followingRows
                }
            }
        }
        .listStyle(.plain)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollAwareTopState(isAtTop: $listAtTop)
        .simultaneousGesture(leadingEdgeSwipe)
        .animation(.easeInOut(duration: 0.18), value: isSearching)
        .animation(.easeInOut(duration: 0.18), value: feedSource)
        // Hidden Cmd+R button — keyboard shortcut for refresh on iPad.
        // Same gesture as pull-to-refresh, no visible chrome.
        .background {
            Button {
                Task { await refreshCurrentSource() }
            } label: { EmptyView() }
            .keyboardShortcut("r", modifiers: .command)
            .opacity(0)
        }
    }

    @ViewBuilder
    private var feedRows: some View {
        feedContextHeader
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 2, leading: 18, bottom: 10, trailing: 18))
            .selectionDisabled()

        if showDigest, feedSource == .category(.top) {
            DigestCardView(viewModel: digest, onDismiss: dismissDigest)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 12, trailing: 18))
                .selectionDisabled()
                .transition(.opacity.combined(with: .move(edge: .top)))
        }

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

    // MARK: - Trending

    @ViewBuilder
    private var trendingRows: some View {
        if let message = trending.errorMessage, trending.items.isEmpty {
            statusRow {
                ContentUnavailableView(
                    "Couldn't compute trends",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            }
        } else if trending.items.isEmpty && trending.isLoading {
            statusRow {
                LoadingStateView(text: "Computing trends…")
            }
        } else if trending.items.isEmpty {
            statusRow {
                ContentUnavailableView {
                    Label("Not enough data yet", systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text("Browse a feed a couple of times and come back — Trending uses score changes between your visits to find stories that are climbing fast.")
                        .multilineTextAlignment(.center)
                }
            }
        } else {
            ForEach(Array(trending.items.enumerated()), id: \.element.id) { index, story in
                storyRow(rank: index + 1, story: story, context: trending.contextLine(for: story))
            }
        }
    }

    // MARK: - Best-of (Algolia)

    @ViewBuilder
    private var bestOfRows: some View {
        if let message = browse.errorMessage, browse.results.isEmpty {
            statusRow {
                ContentUnavailableView {
                    Label("Couldn't load", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") {
                        Task { await browse.refresh() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else if browse.results.isEmpty && browse.isLoading {
            statusRow {
                LoadingStateView(text: "Loading…")
            }
        } else if browse.results.isEmpty {
            statusRow {
                ContentUnavailableView(
                    "Nothing here",
                    systemImage: "tray",
                    description: Text("No stories matched this window.")
                )
            }
        } else {
            ForEach(Array(browse.results.enumerated()), id: \.element.id) { index, story in
                storyRow(rank: index + 1, story: story)
                    .task { await browse.loadMoreIfNeeded(current: story) }
            }
            if browse.isLoading && !browse.results.isEmpty {
                HStack {
                    Spacer()
                    ProgressView().tint(Theme.accent)
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
    }

    // MARK: - Library (SwiftData)

    @ViewBuilder
    private var savedRows: some View {
        if savedStories.isEmpty {
            statusRow {
                ContentUnavailableView(
                    "No Saved Stories",
                    systemImage: "bookmark",
                    description: Text("Swipe a story in the feed and tap Save.")
                )
            }
        } else {
            ForEach(savedStories, id: \.id) { item in
                storyRow(
                    rank: nil,
                    story: item.asHNItem,
                    context: "Saved \(item.savedAt.formatted(.relative(presentation: .named)))"
                )
            }
        }
    }

    // MARK: - Following

    @ViewBuilder
    private var followingRows: some View {
        if followedUsers.isEmpty {
            statusRow {
                ContentUnavailableView(
                    "Not Following Anyone Yet",
                    systemImage: "person.2",
                    description: Text("Tap an author's name on any story or comment, then tap Follow.")
                )
            }
        } else if following.items.isEmpty && following.isLoading {
            statusRow { LoadingStateView(text: "Loading Following…") }
        } else if let message = following.errorMessage, following.items.isEmpty {
            statusRow {
                ContentUnavailableView(
                    "Couldn't load",
                    systemImage: "wifi.exclamationmark",
                    description: Text(message)
                )
            }
        } else if following.items.isEmpty {
            statusRow {
                ContentUnavailableView(
                    "Nothing recent",
                    systemImage: "person.2",
                    description: Text("None of the people you follow have submitted recently.")
                )
            }
        } else {
            ForEach(Array(following.items.enumerated()), id: \.element.id) { _, story in
                storyRow(rank: nil, story: story, context: "by \(story.by ?? "—")")
            }
        }
    }

    @ViewBuilder
    private var readLaterRows: some View {
        if readLaterStories.isEmpty {
            statusRow {
                ContentUnavailableView(
                    "Empty Queue",
                    systemImage: "tray",
                    description: Text("Swipe a story and tap Read Later to queue it up.")
                )
            }
        } else {
            ForEach(readLaterStories, id: \.id) { item in
                storyRow(
                    rank: nil,
                    story: item.asHNItem,
                    context: "Queued \(item.queuedAt.formatted(.relative(presentation: .named)))"
                )
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
                    presentSidebar()
                } label: {
                    // Sized to balance the title block on the right —
                    // the thin-weight 34pt feed name + 22pt icon read
                    // as a heavy mass at the right margin; a small
                    // glyph here makes the hero feel lopsided. Same
                    // tertiary tone and light weight so it stays
                    // ambient — bigger, not louder.
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, height: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show Menu")
            }

            Spacer(minLength: 8)

            Menu {
                feedMenuContent
            } label: {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Image(systemName: feedSource.icon)
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Theme.accent)
                    Text(feedSource.displayTitle)
                        .font(.system(size: 34, weight: .thin, design: .default))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentTransition(.interpolate)
                .animation(.easeInOut(duration: 0.2), value: feedSource)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("Switch feed")
            .accessibilityValue(feedSource.displayTitle)
        }
        .padding(.vertical, 4)
    }

    /// Small inline feed selector that lives in the navigation bar's
    /// principal slot at all scroll positions. Same typographic language
    /// as the hero (thin-weight title, accent-tinted feed icon, quiet
    /// chevron) so the toolbar reads as a continuation of the hero, not
    /// a separate UI region. Tap to switch feeds.
    private var inlineFeedSelector: some View {
        Menu {
            feedMenuContent
        } label: {
            HStack(alignment: .center, spacing: 7) {
                Image(systemName: feedSource.icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Theme.accent)
                Text(feedSource.displayTitle)
                    .font(.system(size: 20, weight: .light, design: .default))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentTransition(.interpolate)
            .animation(.easeInOut(duration: 0.18), value: feedSource)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Switch feed")
        .accessibilityValue(feedSource.displayTitle)
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
                .contentTransition(.numericText(value: Double(viewModel.stories.count)))
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

    /// The shared menu content used by both the big hero selector and
    /// the small inline navbar selector. Sectioned so the user can jump
    /// to any feed (Categories), curated view (Browse), or library
    /// (Saved / Read Later) from a single tap on the title. Every entry
    /// flips `feedSource`, populating the same list scaffolding below —
    /// no modals.
    @ViewBuilder
    private var feedMenuContent: some View {
        Section("Categories") {
            ForEach(HNStoryFeed.allCases) { feed in
                Button {
                    switchSource(to: .category(feed))
                } label: {
                    Label(
                        feed.navigationTitle,
                        systemImage: isActive(.category(feed)) ? "checkmark" : feed.icon
                    )
                }
            }
        }

        Section("Browse") {
            Button {
                switchSource(to: .trending)
            } label: {
                Label(
                    "Trending",
                    systemImage: isActive(.trending) ? "checkmark" : "chart.line.uptrend.xyaxis"
                )
            }
            ForEach(BestOfWindow.allCases) { window in
                Button {
                    switchSource(to: .bestOf(window))
                } label: {
                    Label(
                        "Best of \(window.title)",
                        systemImage: isActive(.bestOf(window)) ? "checkmark" : window.icon
                    )
                }
            }
        }

        Section("Library") {
            Button {
                switchSource(to: .saved)
            } label: {
                Label(
                    "Saved",
                    systemImage: isActive(.saved) ? "checkmark" : "bookmark"
                )
            }
            Button {
                switchSource(to: .readLater)
            } label: {
                Label(
                    "Read Later",
                    systemImage: isActive(.readLater) ? "checkmark" : "tray"
                )
            }
            if !followedUsers.isEmpty {
                Button {
                    switchSource(to: .following)
                } label: {
                    Label(
                        "Following",
                        systemImage: isActive(.following) ? "checkmark" : "person.2"
                    )
                }
            }
        }
    }

    private func isActive(_ source: MainFeedSource) -> Bool {
        feedSource == source
    }


    @ViewBuilder
    private func storyRow(rank: Int?, story: HNItem, context: String? = nil) -> some View {
        StoryRowView(
            rank: rank,
            story: story,
            context: context,
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
                toggleReadLater(story)
            } label: {
                Label(
                    readLaterIDs.contains(story.id) ? "Dequeue" : "Read Later",
                    systemImage: readLaterIDs.contains(story.id) ? "tray.and.arrow.up" : "tray.and.arrow.down"
                )
            }
            .tint(.purple)

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
            let saved = SavedStory(
                id: story.id,
                title: story.title ?? "(untitled)",
                urlString: story.url,
                author: story.by,
                score: story.score,
                descendants: story.descendants
            )
            modelContext.insert(saved)
            // Kick off the background summary pre-fetch so opening
            // this from Saved later is instant + offline-ready.
            SummaryPrefetcher.schedulePrefetch(for: saved, in: modelContext)
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
/// top. Asymmetric thresholds (12pt to come back to "at top", 32pt to
/// leave it) so small inset shifts — e.g. from the navbar's background
/// fading on or off — can't oscillate the state.
private struct ScrollTopStateModifier: ViewModifier {
    @Binding var isAtTop: Bool

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: CGFloat.self) { geometry in
            // Distance scrolled past the natural top. At rest: ~0.
            // Scrolled down by N pts: ~N. Inset shifts roughly cancel
            // here because contentOffset and contentInsets.top move
            // together when the bar resizes.
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, scrollDepth in
            let nextAtTop: Bool
            if isAtTop {
                nextAtTop = scrollDepth < 32
            } else {
                nextAtTop = scrollDepth < 12
            }
            if nextAtTop != isAtTop {
                withAnimation(.easeOut(duration: 0.18)) {
                    isAtTop = nextAtTop
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
        .modelContainer(
            for: [
                SavedStory.self,
                ReadStory.self,
                ReadLaterStory.self,
                ScoreSnapshot.self,
            ],
            inMemory: true
        )
        .environmentObject(AuthViewModel())
}
