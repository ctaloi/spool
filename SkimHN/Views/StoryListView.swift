import SwiftUI
import SwiftData

struct StoryListView: View {
    @StateObject private var viewModel = StoryListViewModel()
    @StateObject private var search = SearchViewModel()
    @StateObject private var browse = AlgoliaFeedViewModel()
    @StateObject private var trending = TrendingFeedViewModel()
    @StateObject private var digest = DigestViewModel()
    @StateObject private var following = FollowingFeedViewModel()
    @StateObject private var mentions = MentionsFeedViewModel()
    @Query private var followedUsers: [FollowedUser]
    @Query private var seenMentions: [SeenMention]
    @AppStorage(SettingsKeys.lastOpenedAt) private var lastOpenedAt: Double = 0
    @AppStorage(SettingsKeys.lastDigestDismissedDay) private var lastDigestDismissedDay: Int = 0
    @AppStorage(SettingsKeys.hideReadStories) private var hideReadStories: Bool = false
    @AppStorage(SettingsKeys.minStoryComments) private var minStoryComments: Int = 0
    @AppStorage(SettingsKeys.recentSearches) private var recentSearchesRaw: String = ""
    @State private var showDigest: Bool = false
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var readLaterPlayer: ReadLaterPlayer
    @Environment(\.modelContext) private var modelContext
    /// Compact-width check — drives whether we render our custom
    /// sidebar-toggle button. On iPad regular the system already
    /// provides one in the toolbar; piling on a second would just
    /// be noise.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \SavedStory.savedAt, order: .reverse) private var savedStories: [SavedStory]
    @Query private var readStories: [ReadStory]
    @Query(sort: \ReadLaterStory.position, order: .forward) private var readLaterStories: [ReadLaterStory]
    @State private var showLogin = false
    @State private var showSubmit = false
    /// Drives what the main list renders. Updated by the sidebar's
    /// onSelect and the toolbar feed picker. Defaults to Top Stories.
    @State private var feedSource: MainFeedSource = .category(.top)
    @State private var searchText = ""
    @State private var selectedStory: HNItem?
    /// True for the brief window between a feed-source change and the
    /// destination VM's first `isLoading = true` actually committing.
    /// Without this bridge, each row builder briefly shows its empty
    /// state on the first frame after a switch, which reads as a flash.
    /// Set synchronously in `switchSource(to:)` so we never miss a
    /// frame, cleared in `.task(id: feedSource)` after the loader
    /// awaits.
    @State private var switchingFeed: Bool = false
    /// Story ID the user just tapped Play on while its summary
    /// prefetch was still in flight. Cleared when playback actually
    /// starts (the .onChange below watches the @Query result and
    /// auto-fires play() once the script is ready).
    @State private var pendingPlayStoryID: Int?
    @EnvironmentObject private var router: AppRouter

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var recentSearches: [String] {
        recentSearchesRaw
            .split(separator: "\u{0001}", omittingEmptySubsequences: true)
            .map(String.init)
    }

    /// Push `query` onto the recent-searches MRU list. Capped at 8.
    /// Separator is the Unicode SOH control character so any
    /// search term containing punctuation round-trips cleanly.
    private func remember(searchQuery query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count >= 2 else { return }
        var list = recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        list.insert(trimmed, at: 0)
        if list.count > 8 { list = Array(list.prefix(8)) }
        recentSearchesRaw = list.joined(separator: "\u{0001}")
    }

    private var savedIDs: Set<Int> { Set(savedStories.map(\.id)) }
    private var readIDs: Set<Int> { Set(readStories.map(\.id)) }
    private var readLaterIDs: Set<Int> { Set(readLaterStories.map(\.id)) }
    private var mentionSeenIDs: Set<Int> { Set(seenMentions.map(\.id)) }

    /// Apply the user's hide-read / min-comments filters while
    /// preserving the source's original 1-based rank. We don't
    /// renumber — the HN-side position is itself information ("this
    /// is currently #5 on HN"), and the filter just hides rows that
    /// shouldn't appear. Returns (originalRank, story) pairs.
    private func filteredRanked(_ source: [HNItem]) -> [(Int, HNItem)] {
        source.enumerated().compactMap { index, story in
            if hideReadStories, readIDs.contains(story.id) { return nil }
            if minStoryComments > 0, (story.descendants ?? 0) < minStoryComments { return nil }
            return (index + 1, story)
        }
    }

    var body: some View {
        NavigationSplitView {
            AppSidebar(
                selection: sidebarSelection,
                onSignIn: { showLogin = true },
                onSignOut: { Task { await auth.logout() } },
                onSubmit: { showSubmit = true }
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
        // `.balanced` keeps all three columns side-by-side on iPad
        // (regular size class). On iPhone (compact), NavigationSplitView
        // collapses to a NavigationStack rooted at the sidebar — the
        // same model as Mail.app. Native back chevron + UIKit's
        // interactivePopGestureRecognizer handle returning to the
        // sidebar from the list and the detail. No custom drawer
        // overlays, no custom edge swipes.
        .navigationSplitViewStyle(.balanced)
        .tint(Theme.accent)
        .onChange(of: feedSource) { _, _ in
            selectedStory = nil
        }
        .onChange(of: router.pendingStoryID) { _, newID in
            // Deep link from Spotlight / widget / notification.
            // Build a stub HNItem for selection — StoryDetailView's
            // VM re-fetches the full record by id on appear, so a
            // bare-id stub is enough.
            guard let id = newID else { return }
            selectedStory = HNItem(
                id: id, type: "story", by: nil, time: nil, text: nil,
                url: nil, title: nil, score: nil, descendants: nil,
                kids: nil, parent: nil, deleted: nil, dead: nil, parts: nil
            )
            _ = router.consumeStoryID()
        }
        .onChange(of: auth.isLoggedIn) { _, nowLoggedIn in
            // Mentions needs a username — if the user just signed in
            // (or out) while on the Mentions source, re-fire the
            // loader. Other sources don't depend on auth.
            guard case .mentions = feedSource else { return }
            Task {
                if nowLoggedIn {
                    await mentions.load(username: auth.username)
                }
            }
        }
        .sheet(isPresented: $showLogin) {
            LoginView().environmentObject(auth)
        }
        .sheet(isPresented: $showSubmit) {
            SubmitView().environmentObject(auth)
        }
    }

    /// Optional binding the sidebar's `List(selection:)` writes
    /// when the user taps a tagged row. Tapping flows through
    /// switchSource so we get the synchronous `switchingFeed` flag
    /// that prevents an empty-state flash on the first frame after
    /// the swap.
    private var sidebarSelection: Binding<MainFeedSource?> {
        Binding(
            get: { feedSource },
            set: { newValue in
                if let newValue, newValue != feedSource {
                    switchSource(to: newValue)
                }
            }
        )
    }

    /// Centralized switch. Sets `switchingFeed` synchronously so the
    /// destination row builder shows its loading state on the first
    /// frame after the flip, without waiting for the destination
    /// VM's isLoading to commit. NavigationSplitView's compact
    /// collapse handles bringing the content column forward — no
    /// manual column manipulation here.
    private func switchSource(to source: MainFeedSource) {
        switchingFeed = true
        feedSource = source
    }

    /// Fires whenever `feedSource` changes. Single path for every
    /// loader, including category — owning the load here (rather than
    /// dispatching via `feed.didSet`) keeps `switchingFeed` correctly
    /// bracketed by the `.task(id: feedSource)` lifetime.
    private func loadCurrentSource() async {
        switch feedSource {
        case .category(let newFeed):
            // Assigning .feed clears stories synchronously via the
            // setter's didSet; this assignment is a no-op when feed
            // already matches.
            viewModel.feed = newFeed
            await viewModel.reload()
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
        case .mentions:
            await mentions.load(username: auth.username)
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

    /// Bring the digest back after the user dismissed it (or on
    /// demand even before today's first auto-show). Cheap: just
    /// re-runs `generate` with the currently visible top stories
    /// and flips the visibility flag. Clears `lastDigestDismissedDay`
    /// so the user's earlier dismissal doesn't suppress it again.
    private func recallDigest() {
        lastDigestDismissedDay = 0
        digest.generate(stories: viewModel.stories)
        withAnimation(.easeOut(duration: 0.35)) {
            showDigest = true
        }
    }

    /// Quiet pill that takes the digest card's row slot when no
    /// digest is currently visible. Tapping regenerates and reveals
    /// the digest — gives the user a way back in without scrolling
    /// or hunting through a menu. Uses iOS 26's Liquid Glass button
    /// style so the system draws the translucent capsule + pressed
    /// state.
    private var digestRecallPill: some View {
        Button(action: recallDigest) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .symbolEffect(.pulse, options: .nonRepeating)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Today's Digest")
                        .font(.subheadline.weight(.semibold))
                    Text("What's on HN today, in a paragraph.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.glass)
        .tint(Theme.accent)
        .accessibilityHint("Reveals a generated summary of today's top stories.")
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
        case .mentions:
            await mentions.load(username: auth.username)
        }
    }

    // MARK: - Content column

    private var listContent: some View {
        content
            // Native large title — collapses to inline as the user
            // scrolls, the standard iOS pattern that Mail / Settings
            // / Notes all use.
            .navigationTitle(isSearching ? "Search" : feedSource.displayTitle)
            // iOS 26 navigation subtitle — system-rendered second line
            // under the large title (and the inline title once it
            // collapses). Replaces the in-list "30 stories · Updated
            // 2m ago" row.
            .navigationSubtitle(navigationSubtitle)
            .navigationBarTitleDisplayMode(.large)
            // Hide the system back chevron only on compact; iPad
            // regular still relies on the system sidebar toggle.
            .navigationBarBackButtonHidden(horizontalSizeClass == .compact)
            .toolbar {
                sidebarToggleToolbarItem
                listenShortcutToolbarItem
                feedPickerToolbarItem
            }
            // Native search drawer for feeds that support it. iOS
            // renders the search field in the navbar, handles focus,
            // cancellation, and the keyboard. Auto-hides on scroll.
            .searchable(
                text: $searchText,
                placement: feedSource.supportsSearch ? .navigationBarDrawer(displayMode: .automatic) : .toolbar,
                prompt: "Search Hacker News"
            )
            .searchSuggestions {
                if searchText.isEmpty {
                    ForEach(recentSearches, id: \.self) { suggestion in
                        Label(suggestion, systemImage: "clock.arrow.circlepath")
                            .searchCompletion(suggestion)
                    }
                }
            }
            .onSubmit(of: .search) {
                remember(searchQuery: searchText)
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .refreshable {
                await refreshCurrentSource()
            }
            .task(id: feedSource) {
                await loadCurrentSource()
                switchingFeed = false
            }
            .task {
                SavedStoryIndexer.syncAll(savedStories)
                backfillReadLaterPositionsIfNeeded()
            }
            // Phase 6: when the playlist finishes an item, pluck
            // it from the Read Later queue. This is what makes
            // Read Later a queue rather than an archive — items
            // leave once they've been consumed (auto-archive on
            // listen). Captured by reference so we can read
            // modelContext + the live @Query result.
            .task {
                readLaterPlayer.onItemFinished = { finished in
                    Task { @MainActor in
                        if let row = readLaterStories.first(where: { $0.id == finished.id }) {
                            modelContext.delete(row)
                        }
                    }
                }
            }
            // Auto-start the playlist when a Play tap landed before
            // the summary was ready. The user tapped, we stashed
            // pendingPlayStoryID, fired prefetch — once the script
            // shows up via the @Query refresh, this catches it and
            // calls play().
            .onChange(of: readLaterStories.map(\.cachedArticleSummary)) { _, _ in
                guard let pendingID = pendingPlayStoryID,
                      let item = readLaterStories.first(where: { $0.id == pendingID }),
                      item.playlistScript != nil,
                      let index = readLaterStories.firstIndex(where: { $0.id == pendingID })
                else { return }
                pendingPlayStoryID = nil
                readLaterPlayer.play(items: readLaterStories, startingAt: index)
            }
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

    /// Replaces the default back chevron with a sidebar glyph in the
    /// same leading slot. Dismiss pops the navigation stack — on
    /// compact that returns to the sidebar (the root of the
    /// collapsed NavigationStack). Native edge-swipe still works.
    @ToolbarContentBuilder
    private var sidebarToggleToolbarItem: some ToolbarContent {
        if horizontalSizeClass == .compact {
            ToolbarItem(placement: .topBarLeading) {
                SidebarToggleButton()
            }
        }
    }

    /// One-tap shortcut to the Listen queue from any feed. Pairs
    /// the headphones icon with a small accent-dot badge when there
    /// are items waiting, so a glance tells the user the queue is
    /// non-empty without taking up label space.
    @ToolbarContentBuilder
    private var listenShortcutToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                feedSource = .readLater
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "headphones")
                    if !readLaterStories.isEmpty {
                        Text("\(readLaterStories.count)")
                            .font(.system(size: 10, weight: .heavy).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red, in: Capsule(style: .continuous))
                            .offset(x: 8, y: -7)
                    }
                }
            }
            .accessibilityLabel(readLaterStories.isEmpty
                                ? "Open Listen queue"
                                : "Open Listen queue, \(readLaterStories.count) items")
        }
    }

    /// Toolbar feed picker — single-tap shortcut to switch the active
    /// feed without going back to the sidebar. Renders as a system
    /// Menu button with the current feed's icon + a chevron.
    @ToolbarContentBuilder
    private var feedPickerToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                feedMenuContent
            } label: {
                Label("Switch Feed", systemImage: feedSource.icon)
            }
            .accessibilityLabel("Switch feed")
            .accessibilityValue(feedSource.displayTitle)
        }
    }

    /// Single shared list so the hero stays visible in every source
    /// (categories, search, trending, best-of, library) and during
    /// their error / loading variants.
    @ViewBuilder
    private var content: some View {
        List(selection: $selectedStory) {
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
                case .mentions: mentionsRows
                }
            }
        }
        .listStyle(.plain)
        // iOS 26 — give the navbar a soft Liquid Glass scroll edge
        // effect at the top of the list. Matches Mail / Notes.
        .scrollEdgeEffectStyle(.soft, for: .top)
        .animation(.easeInOut(duration: 0.18), value: isSearching)
        // Slightly slower than search toggle — feed switches are
        // bigger conceptual changes and a 0.28s crossfade reads as
        // intentional rather than glitchy.
        .animation(.easeInOut(duration: 0.28), value: feedSource)
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
        // Digest is AI-driven — only ever render on devices where
        // the model is actually available. digest.canRun checks the
        // same SummaryService.availability under the hood, so the
        // pill case is implicitly gated; the card case needs an
        // explicit gate so users without AI never see it auto-fire
        // when they land on Top.
        if SummaryService.shared.isAvailable {
            if showDigest, feedSource == .category(.top) {
                DigestCardView(viewModel: digest, onDismiss: dismissDigest)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 12, trailing: 18))
                    .selectionDisabled()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if feedSource == .category(.top),
                      !viewModel.stories.isEmpty,
                      digest.canRun {
                digestRecallPill
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 12, trailing: 18))
                    .selectionDisabled()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
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
        } else if viewModel.stories.isEmpty && (viewModel.isLoading || switchingFeed) {
            statusRow {
                LoadingStateView(text: "Loading \(viewModel.feed.title.lowercased())…")
            }
        } else {
            let filtered = filteredRanked(viewModel.stories)
            let hasMore = viewModel.stories.count < viewModel.totalAvailable

            ForEach(filtered, id: \.1.id) { rank, story in
                storyRow(rank: rank, story: story)
                    .task { await viewModel.loadMoreIfNeeded(current: story) }
            }

            if hasMore {
                // Auto-pagination sentinel. Two responsibilities:
                // 1. Re-fire as a `.task(id: ...)` whenever the
                //    backing story count changes so we chain
                //    through filtered batches that pass nothing.
                // 2. Render as a spinner so the user sees we're
                //    still working when their filter is aggressive.
                HStack {
                    Spacer()
                    ProgressView().tint(Theme.accent)
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .task(id: viewModel.stories.count) {
                    await viewModel.loadMore()
                }
            } else if filtered.isEmpty {
                // We've fetched every available story and the filter
                // still passes nothing. Surface an actionable empty
                // state instead of leaving a blank list.
                statusRow {
                    ContentUnavailableView {
                        Label("No stories match your filter", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("Loosen the minimum-comments threshold or turn off Hide Read in Settings.")
                    }
                }
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
        } else if trending.items.isEmpty && (trending.isLoading || switchingFeed) {
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
            ForEach(filteredRanked(trending.items), id: \.1.id) { rank, story in
                storyRow(rank: rank, story: story, context: trending.contextLine(for: story))
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
        } else if browse.results.isEmpty && (browse.isLoading || switchingFeed) {
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
            let filtered = filteredRanked(browse.results)

            ForEach(filtered, id: \.1.id) { rank, story in
                storyRow(rank: rank, story: story)
                    .task { await browse.loadMoreIfNeeded(current: story) }
            }

            if browse.hasMore {
                // Same auto-pagination pattern as the category feed —
                // .task(id: count) re-fires each time results grow,
                // so an aggressive filter keeps fetching until the
                // page list is exhausted.
                HStack {
                    Spacer()
                    ProgressView().tint(Theme.accent)
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .task(id: browse.results.count) {
                    await browse.loadMore()
                }
            } else if filtered.isEmpty {
                statusRow {
                    ContentUnavailableView {
                        Label("No stories match your filter", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("Loosen the minimum-comments threshold or turn off Hide Read in Settings.")
                    }
                }
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
        } else if following.items.isEmpty && (following.isLoading || switchingFeed) {
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
                    "Nothing to listen to yet",
                    systemImage: "headphones",
                    description: Text("Tap the Listen icon on any story to queue it for audio playback.")
                )
            }
        } else {
            playAllCard
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 12, trailing: 18))
                .selectionDisabled()

            ForEach(readLaterStories, id: \.id) { item in
                readLaterPlaylistRow(item: item)
            }
            .onMove(perform: moveReadLater)
            .onDelete(perform: deleteReadLater)
        }
    }

    /// Upgrade path: rows that existed before we added `position`
    /// all land with position = 0 by SwiftData's default-value
    /// migration. That makes the @Query sort ambiguous and renders
    /// the queue in arbitrary order. On every launch, check
    /// whether more than one row shares position 0 — if so,
    /// backfill positions in queuedAt-newest-first order so the
    /// queue matches what the user remembers.
    private func backfillReadLaterPositionsIfNeeded() {
        let zeroes = readLaterStories.filter { $0.position == 0 }
        guard zeroes.count > 1 else { return }
        let sorted = readLaterStories.sorted { lhs, rhs in
            lhs.queuedAt > rhs.queuedAt
        }
        for (index, story) in sorted.enumerated() {
            story.position = index
        }
    }

    /// Drag-to-reorder. Mutates the in-memory @Query array's
    /// `position` fields so the next render comes back in the new
    /// order. Persistence is automatic — SwiftData autosaves on
    /// property changes within the bound model context.
    private func moveReadLater(from source: IndexSet, to destination: Int) {
        var stories = readLaterStories
        stories.move(fromOffsets: source, toOffset: destination)
        for (index, story) in stories.enumerated() {
            story.position = index
        }
    }

    /// Swipe-to-delete from the queue.
    private func deleteReadLater(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(readLaterStories[index])
        }
    }

    /// Top-of-queue card — "Play All" pill + queue-level totals.
    /// When the player is already running, the same card swaps to
    /// a "Now Playing" surface showing the current item's title +
    /// position. Tap toggles play/pause.
    @ViewBuilder
    private var playAllCard: some View {
        let totalSeconds = readLaterStories.reduce(0) { $0 + $1.estimatedListenSeconds }
        let isPlayingThisQueue = readLaterPlayer.isActive &&
            readLaterPlayer.queue.map(\.id) == readLaterStories.map(\.id)

        Button {
            handlePlayAllTap()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: playAllIconName(isPlaying: isPlayingThisQueue))
                    .font(.title2)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 1) {
                    Text(isPlayingThisQueue ? "Now Listening" : "Play All")
                        .font(.headline)
                    Text(playAllSubtitle(totalSeconds: totalSeconds,
                                          isPlayingThisQueue: isPlayingThisQueue))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.glass)
        .tint(Theme.accent)
        .accessibilityHint("Plays the article and discussion summary for each queued story.")
    }

    private func playAllIconName(isPlaying: Bool) -> String {
        if isPlaying {
            return readLaterPlayer.state == .playing ? "pause.fill" : "play.fill"
        }
        return "play.fill"
    }

    private func playAllSubtitle(totalSeconds: Int, isPlayingThisQueue: Bool) -> String {
        if isPlayingThisQueue, let current = readLaterPlayer.currentItem {
            return current.title
        }
        let count = readLaterStories.count
        let mins = max(1, totalSeconds / 60)
        return "\(count) \(count == 1 ? "story" : "stories") · ~\(mins) min listen"
    }

    /// One queued-story row with title / meta on the left and an
    /// individual play button on the right. Tapping the row body
    /// still opens the detail view via List's selection (we add a
    /// `.tag` like every other story row); the trailing play button
    /// is a separate target.
    @ViewBuilder
    private func readLaterPlaylistRow(item: ReadLaterStory) -> some View {
        let isCurrent = readLaterPlayer.currentItem?.id == item.id

        HStack(alignment: .center, spacing: 12) {
            StoryRowView(
                rank: nil,
                story: item.asHNItem,
                context: "Queued \(item.queuedAt.formatted(.relative(presentation: .named)))",
                isRead: readIDs.contains(item.id),
                isSaved: savedIDs.contains(item.id)
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                handlePlayTap(for: item)
            } label: {
                if pendingPlayStoryID == item.id {
                    // Brewing: prefetch in flight, will autoplay
                    // when the cache lands.
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: rowPlayIconName(isCurrent: isCurrent))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .tint(Theme.accent)
            .accessibilityLabel(rowPlayAccessibilityLabel(isCurrent: isCurrent, title: item.title))
        }
        .padding(.vertical, 2)
        .background(
            isCurrent
                ? Theme.accent.opacity(0.08)
                : Color.clear,
            in: .rect(cornerRadius: 10, style: .continuous)
        )
        .tag(item.asHNItem)
    }

    /// Per-row Play handler. If the item already has a script,
    /// starts immediately. If not, kicks off prefetch for that
    /// item and stashes its id in `pendingPlayStoryID` — the
    /// .onChange below auto-starts once the summary lands.
    private func handlePlayTap(for item: ReadLaterStory) {
        let isCurrent = readLaterPlayer.currentItem?.id == item.id
        if isCurrent {
            readLaterPlayer.toggle()
            return
        }
        if item.playlistScript != nil,
           let index = readLaterStories.firstIndex(where: { $0.id == item.id }) {
            pendingPlayStoryID = nil
            readLaterPlayer.play(items: readLaterStories, startingAt: index)
            return
        }
        // Not ready yet — prefetch + wait.
        pendingPlayStoryID = item.id
        SummaryPrefetcher.schedulePrefetch(for: item, in: modelContext)
    }

    /// Play All handler. If everything in the queue already has a
    /// script, starts immediately. If the first item needs a
    /// prefetch, kicks one off + stashes pendingPlayStoryID so the
    /// auto-start fires as soon as that first item is ready.
    private func handlePlayAllTap() {
        let isPlayingThisQueue = readLaterPlayer.isActive &&
            readLaterPlayer.queue.map(\.id) == readLaterStories.map(\.id)
        if isPlayingThisQueue {
            readLaterPlayer.toggle()
            return
        }
        guard let first = readLaterStories.first else { return }
        if first.playlistScript != nil {
            pendingPlayStoryID = nil
            readLaterPlayer.play(items: readLaterStories)
            return
        }
        // Schedule prefetch for every item missing summaries so
        // the playlist can stream through without stalling on
        // each row.
        for item in readLaterStories where item.cachedArticleSummary == nil {
            SummaryPrefetcher.schedulePrefetch(for: item, in: modelContext)
        }
        pendingPlayStoryID = first.id
    }

    private func rowPlayIconName(isCurrent: Bool) -> String {
        guard isCurrent else { return "play.fill" }
        return readLaterPlayer.state == .playing ? "pause.fill" : "play.fill"
    }

    private func rowPlayAccessibilityLabel(isCurrent: Bool, title: String) -> String {
        if isCurrent {
            return readLaterPlayer.state == .playing
                ? "Pause \(title)"
                : "Resume \(title)"
        }
        return "Play \(title)"
    }

    // MARK: - Mentions

    @ViewBuilder
    private var mentionsRows: some View {
        if !auth.isLoggedIn {
            statusRow {
                ContentUnavailableView(
                    "Sign In for Mentions",
                    systemImage: "at",
                    description: Text("Sign in to your Hacker News account to see replies to your comments.")
                )
            }
        } else if mentions.items.isEmpty && (mentions.isLoading || switchingFeed) {
            statusRow { LoadingStateView(text: "Loading Mentions…") }
        } else if let message = mentions.errorMessage, mentions.items.isEmpty {
            statusRow {
                ContentUnavailableView(
                    "Couldn't load",
                    systemImage: "wifi.exclamationmark",
                    description: Text(message)
                )
            }
        } else if mentions.items.isEmpty {
            statusRow {
                ContentUnavailableView(
                    "No Mentions Yet",
                    systemImage: "at",
                    description: Text("Replies to your comments will show up here.")
                )
            }
        } else {
            ForEach(mentions.items) { record in
                mentionRow(record: record)
            }
        }
    }

    /// One Mentions row. Wrapped in a Button (not the List's
    /// selection-by-tag pattern) for two reasons:
    /// 1. Multiple mentions can point to the same host story —
    ///    selection-by-tag would collapse them to the same Hashable
    ///    HNItem and highlight every row when one is "selected".
    /// 2. We want mark-as-seen semantics that match iOS Mail: the dot
    ///    stays until the user actually opens the row, not when it
    ///    happens to scroll into view.
    @ViewBuilder
    private func mentionRow(record: MentionRecord) -> some View {
        Button {
            if !mentionSeenIDs.contains(record.reply.id) {
                modelContext.insert(SeenMention(id: record.reply.id))
            }
            selectedStory = mentionAsHNItem(record)
        } label: {
            MentionRowView(
                record: record,
                isUnread: !mentionSeenIDs.contains(record.reply.id)
            )
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        .listRowSeparator(.hidden)
    }

    /// Adapt a mention into the selection-driven HNItem currency the
    /// rest of the list uses — selecting a row sets `selectedStory`
    /// and the detail column fetches by ID via HNAPI.
    private func mentionAsHNItem(_ record: MentionRecord) -> HNItem {
        HNItem(
            id: record.parentComment.storyID,
            type: "story",
            by: nil,
            time: nil,
            text: nil,
            url: nil,
            title: record.parentComment.storyTitle ?? "Story",
            score: nil,
            descendants: nil,
            kids: nil,
            parent: nil,
            deleted: nil,
            dead: nil,
            parts: nil
        )
    }

    /// Thin stats row between the search drawer and the first story.
    /// Feed name lives in the hero now, so this is just
    /// String fed to iOS 26's `.navigationSubtitle` modifier so the
    /// "N stories · Updated Xm ago" line lives in the native title
    /// region instead of a custom in-list row.
    private var navigationSubtitle: String {
        guard !viewModel.stories.isEmpty else { return "" }
        switch feedSource {
        case .category:
            var parts = ["\(viewModel.stories.count) stories"]
            if let date = viewModel.lastReloadedAt {
                parts.append(date.formatted(.relative(presentation: .named)))
            }
            return parts.joined(separator: " · ")
        case .trending:
            return "\(trending.items.count) trending"
        case .bestOf:
            return "\(browse.results.count) stories"
        case .following:
            return "\(following.items.count) recent"
        case .mentions:
            return "\(mentions.items.count) mentions"
        case .saved, .readLater:
            return ""
        }
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
                    "Listen",
                    systemImage: isActive(.readLater) ? "checkmark" : "headphones"
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
            if auth.isLoggedIn {
                Button {
                    switchSource(to: .mentions)
                } label: {
                    Label(
                        "Mentions",
                        systemImage: isActive(.mentions) ? "checkmark" : "at"
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
                    readLaterIDs.contains(story.id) ? "Remove" : "Listen",
                    systemImage: readLaterIDs.contains(story.id) ? "minus.circle.fill" : "headphones"
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
            SavedStoryIndexer.deindex(story.id)
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
            // Surface in iOS system Spotlight search.
            SavedStoryIndexer.index(saved)
        }
    }

    private func toggleReadLater(_ story: HNItem) {
        if let existing = readLaterStories.first(where: { $0.id == story.id }) {
            modelContext.delete(existing)
        } else {
            let nextPosition = (readLaterStories.map(\.position).max() ?? -1) + 1
            let queued = ReadLaterStory(
                id: story.id,
                title: story.title ?? "(untitled)",
                urlString: story.url,
                author: story.by,
                score: story.score,
                descendants: story.descendants,
                position: nextPosition
            )
            modelContext.insert(queued)
            SummaryPrefetcher.schedulePrefetch(for: queued, in: modelContext)
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

/// Three-line "show sidebar" button placed in the leading toolbar
/// slot on compact width. Uses `\.dismiss` so the pop goes through
/// the same NavigationStack mechanism the system back chevron would —
/// edge-swipe back to sidebar still works, only the visible glyph
/// changes.
private struct SidebarToggleButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "line.3.horizontal")
        }
        .accessibilityLabel("Show Sidebar")
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
                FollowedUser.self,
                SeenMention.self,
            ],
            inMemory: true
        )
        .environmentObject(AuthViewModel())
        .environmentObject(AppRouter())
}
