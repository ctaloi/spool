import SwiftUI
import SwiftData

struct StoryListView: View {
    @StateObject private var viewModel = StoryListViewModel()
    @StateObject private var search = SearchViewModel()
    @StateObject private var browse = AlgoliaFeedViewModel()
    @StateObject private var trending = TrendingFeedViewModel()
    @StateObject private var following = FollowingFeedViewModel()
    @StateObject private var mentions = MentionsFeedViewModel()
    @Query private var followedUsers: [FollowedUser]
    @Query private var seenMentions: [SeenMention]
    @AppStorage(SettingsKeys.hideReadStories) private var hideReadStories: Bool = false
    @AppStorage(SettingsKeys.minStoryComments) private var minStoryComments: Int = 0
    @AppStorage(SettingsKeys.recentSearches) private var recentSearchesRaw: String = ""
    @AppStorage(SettingsKeys.hiddenFeeds) private var hiddenFeedsRaw: String = ""
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var spoolPlayer: SpoolPlayer
    @Environment(\.modelContext) private var modelContext
    /// Compact-width check — drives whether we render our custom
    /// sidebar-toggle button. On iPad regular the system already
    /// provides one in the toolbar; piling on a second would just
    /// be noise.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \SavedStory.savedAt, order: .reverse) private var savedStories: [SavedStory]
    @Query private var readStories: [ReadStory]
    @Query(filter: #Predicate<SpooledStory> { $0.archivedAt == nil },
           sort: \SpooledStory.position, order: .forward)
    private var spool: [SpooledStory]
    @Query(filter: #Predicate<SpooledStory> { $0.archivedAt != nil },
           sort: \SpooledStory.queuedAt, order: .reverse)
    private var archive: [SpooledStory]
    @State private var showLogin = false
    @State private var showSubmit = false
    /// DEBUG-only screenshot harness — toggled by the launch arg
    /// `-SpoolShowSheet settings|login|submit|nowplaying`. Lets the
    /// CI / capture script reach modal sheets without UI taps.
    @State private var showSettings = false
    /// Drives the three-column visibility on iPad. The custom
    /// leading-edge sidebar toggle in AppSidebar flips this between
    /// `.all` (sidebar visible) and `.doubleColumn` (sidebar hidden,
    /// content + detail side-by-side).
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// Drives the NowPlayingView sheet. Set true by Play All and by
    /// tapping a row inside the Spool queue (which also primes the
    /// player to start at that item). The mini player at the
    /// scene-root bottom inset already provides a "Now Playing" tap
    /// affordance, but the user expects the queue itself to be a
    /// one-tap entry point into playback.
    @State private var showNowPlaying = false
    /// Drives what the main list renders. Updated by the sidebar's
    /// onSelect and the toolbar feed picker. Defaults to Top Stories.
    @State private var feedSource: MainFeedSource = .category(.top)
    /// Optional sidebar selection — separate from `feedSource` so
    /// iOS can clear the visual highlight on compact-collapse
    /// without us snapping it back. `feedSource` stays as the
    /// authoritative active source; this drives the sidebar's
    /// `List(selection:)` binding only.
    @State private var sidebarSelectionState: MainFeedSource?
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

    /// Single Bool the auto-play onChange watches. Was an
    /// `Array<String?>` derived from every spool row's summary —
    /// allocated on every SwiftUI body invalidation. This is the
    /// minimum signal: "the row we're parked on has a playable
    /// script." Stable while nothing is pending and while the
    /// pending row's prefetch is still in flight.
    private var pendingPlayReadyTrigger: Bool {
        guard let pendingID = pendingPlayStoryID else { return false }
        return spool.contains { $0.id == pendingID && $0.playlistScript != nil }
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
    private var spooledIDs: Set<Int> { Set(spool.map(\.id)) }
    private var mentionSeenIDs: Set<Int> { Set(seenMentions.map(\.id)) }

    /// Apply the user's hide-read / min-comments filters. We don't
    /// renumber or rank anymore — the row UI no longer surfaces a
    /// position number, so we just return the visible stories.
    private func filteredStories(_ source: [HNItem]) -> [HNItem] {
        source.filter { story in
            if hideReadStories, readIDs.contains(story.id) { return false }
            if minStoryComments > 0, (story.descendants ?? 0) < minStoryComments { return false }
            return true
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            AppSidebar(
                selection: sidebarSelection,
                onSignIn: { showLogin = true },
                onSignOut: { Task { await auth.logout() } },
                onSubmit: { showSubmit = true },
                onToggleSidebar: {
                    withAnimation {
                        columnVisibility = columnVisibility == .all
                            ? .doubleColumn
                            : .all
                    }
                }
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
        .onChange(of: router.pendingFeedSource) { _, keyword in
            guard let keyword,
                  let source = MainFeedSource.from(keyword: keyword)
            else { return }
            selectedStory = nil
            if source != feedSource {
                switchSource(to: source)
            }
            sidebarSelectionState = source
            _ = router.consumeFeedSource()
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
        #if DEBUG
        .task(id: router.pendingSheet) {
            guard let sheet = router.pendingSheet else { return }
            // Small delay so the launch overlay has dismissed before
            // we present — without this, the sheet animates up under
            // the splash and ends up half-visible.
            try? await Task.sleep(for: .milliseconds(1_500))
            switch sheet {
            case "settings":   showSettings = true
            case "login":      showLogin = true
            case "submit":     showSubmit = true
            case "nowplaying": showNowPlaying = true
            default: break
            }
            router.pendingSheet = nil
        }
        #endif
        .sheet(isPresented: $showLogin) {
            LoginView().environmentObject(auth)
        }
        .sheet(isPresented: $showSubmit) {
            SubmitView().environmentObject(auth)
        }
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView()
                .environmentObject(spoolPlayer)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(auth)
        }
    }

    /// Optional binding the sidebar's `List(selection:)` writes
    /// when the user taps a tagged row. Tapping flows through
    /// switchSource so we get the synchronous `switchingFeed` flag
    /// that prevents an empty-state flash on the first frame after
    /// the swap.
    private var sidebarSelection: Binding<MainFeedSource?> {
        Binding(
            get: { sidebarSelectionState },
            set: { newValue in
                // iOS clears sidebar selection on compact-mode
                // navigation transitions. Pass that nil through
                // verbatim so the highlight drops naturally —
                // previously we ignored nil and re-asserted the
                // active source, which felt "stuck".
                sidebarSelectionState = newValue
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
    ///
    /// Also syncs the sidebar selection state so the highlight
    /// follows the active source when the change comes from
    /// somewhere other than the sidebar (e.g., the toolbar feed
    /// picker or a deep link).
    private func switchSource(to source: MainFeedSource) {
        switchingFeed = true
        feedSource = source
        sidebarSelectionState = source
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
            // First-hit-after-switch occasionally returns an empty
            // response from Algolia even though the same URL works on
            // pull-to-refresh a moment later. If we landed empty
            // without an error, simulate the user's pull and try once
            // more — harmless when the window is legitimately empty.
            if browse.results.isEmpty, browse.errorMessage == nil {
                await browse.refresh()
            }
        case .saved, .spool, .archive:
            // SwiftData @Query keeps these live; nothing to fetch.
            break
        case .following:
            await following.load(usernames: followedUsers.map(\.username))
        case .mentions:
            await mentions.load(username: auth.username)
        }
    }

    // MARK: - Section summary

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
        case .saved, .spool, .archive:
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
            // Note: `.navigationSubtitle` (iOS 26) was previously set
            // here, but with a transparent scrollEdge appearance and
            // our editorial thin title font it caused the system to
            // squeeze title+subtitle into the default single-line
            // largeTitle frame, clipping the title's ascenders. The
            // section-summary card immediately below the navbar
            // already surfaces the same "N stories" count, so we drop
            // the subtitle to reclaim vertical room for the title.
            .navigationBarTitleDisplayMode(.large)
            // Hide the system back chevron only on compact; iPad
            // regular still relies on the system sidebar toggle.
            .navigationBarBackButtonHidden(horizontalSizeClass == .compact)
            .toolbar {
                sidebarToggleToolbarItem
                listenShortcutToolbarItem
                feedPickerToolbarItem
            }
            // Native search drawer for feeds that support it. Library
            // and curated sources (Spool, Saved, Archive, Mentions,
            // Following, Trending) don't run an Algolia query, so we
            // hide the search field entirely on those rather than
            // surface a non-functional `.toolbar`-placement field.
            .modifier(StoryListConditionalSearchable(
                isActive: feedSource.supportsSearch,
                text: $searchText,
                recentSearches: recentSearches,
                onSubmit: { remember(searchQuery: searchText) }
            ))
            .refreshable {
                await refreshCurrentSource()
            }
            // Was .task(id: feedSource), but the .modifier above
            // flips its if/else branch when supportsSearch changes
            // (category ↔ best-of), and that branch flip would
            // interrupt the .task body's in-flight fetch — best-of
            // landed empty on the very first visit from a category,
            // worked fine on every subsequent visit. Routing through
            // .onChange + an unstructured Task decouples the load
            // from the modifier chain's lifecycle.
            .onChange(of: feedSource, initial: true) { _, _ in
                Task {
                    await loadCurrentSource()
                    switchingFeed = false
                }
            }
            .task {
                SavedStoryIndexer.syncAll(savedStories)
                backfillSpoolPositionsIfNeeded()
            }
            // Phase 6: when the playlist finishes an item, pluck
            // it from the Spool queue. This is what makes
            // Spool a queue rather than an archive — items
            // leave once they've been consumed (auto-archive on
            // listen). Captured by reference so we can read
            // modelContext + the live @Query result.
            .task {
                let context = modelContext
                spoolPlayer.onItemFinished = { finished in
                    Task { @MainActor in
                        // Don't delete — move to the Archive. The user
                        // can restore it later, or delete it for real
                        // from the archive view. Keeping the row in
                        // the same table (filtered by `archivedAt`)
                        // means no SwiftData migration ceremony.
                        //
                        // Fetch via a fresh FetchDescriptor instead of
                        // closing over the @Query snapshot — the
                        // snapshot can diverge from live data, and
                        // mutating an orphaned SwiftData model after
                        // it's been deleted from context is a crash.
                        let finishedID = finished.id
                        let descriptor = FetchDescriptor<SpooledStory>(
                            predicate: #Predicate { $0.id == finishedID }
                        )
                        if let row = try? context.fetch(descriptor).first {
                            row.archivedAt = .now
                        }
                    }
                }
            }
            // Auto-start the playlist when a Play tap landed before
            // the summary was ready. The user tapped, we stashed
            // pendingPlayStoryID, fired prefetch — once the script
            // shows up via the @Query refresh, this catches it and
            // calls play().
            // Was: `onChange(of: spool.map(\.cachedArticleSummary))`,
            // which allocated an array of optional strings on every
            // body invalidation. The cheaper signal is "is the row
            // we're waiting on actually ready" — a single Bool that
            // only flips on the relevant prefetch completion.
            .onChange(of: pendingPlayReadyTrigger) { _, isReady in
                guard isReady, pendingPlayStoryID != nil else { return }
                pendingPlayStoryID = nil
                spoolPlayer.play(items: spool)
                // The user tapped Play All before the summary was
                // ready; now that we're actually starting, surface
                // the now-playing sheet so the "Preparing…" → "Now
                // Playing" transition is visible to them.
                showNowPlaying = true
            }
            .onChange(of: viewModel.lastReloadedAt) { _, _ in
                TrendingService.recordSnapshots(for: viewModel.stories, in: modelContext)
            }
            .onChange(of: feedSource) { _, _ in
            }
            .onChange(of: searchText) { _, new in
                search.update(query: new)
            }
            .sensoryFeedback(.success, trigger: savedStories.count)
            .sensoryFeedback(.success, trigger: spool.count)
            .sensoryFeedback(.success, trigger: archive.count)
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
                StoryListSidebarToggleButton()
            }
        }
    }

    /// One-tap shortcut to the Spool from any feed. Pairs the
    /// headphones icon with a small accent-dot badge when there are
    /// items waiting, so a glance tells the user the spool is non-
    /// empty without taking up label space.
    ///
    /// Hidden when the Spool feed is already the active source — the
    /// shortcut would just point at where the user already is, and
    /// the duplicate headphones glyph (toolbar + empty-state hero)
    /// looked broken.
    @ToolbarContentBuilder
    private var listenShortcutToolbarItem: some ToolbarContent {
        // Only surface when there's actually content to play. The
        // sidebar's Spool section is always reachable for the
        // empty-state onboarding flow; the toolbar shortcut is for
        // quick access during reading, which only matters once the
        // queue is non-empty.
        //
        // The count badge previously used an offset overlay that
        // clipped 2-digit counts at the trailing edge of the
        // toolbar's tap area. Inline `Label` with headphones +
        // monospaced-digit count renders the full number within
        // the toolbar slot at every size.
        if feedSource != .spool, !spool.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    feedSource = .spool
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "headphones")
                        Text("\(spool.count)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .contentTransition(.numericText(value: Double(spool.count)))
                    }
                }
                .accessibilityLabel("Open Spool, \(spool.count) items")
            }
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
                feedSubtitleRow
                switch feedSource {
                case .category: feedRows
                case .trending: trendingRows
                case .bestOf: bestOfRows
                case .saved: savedRows
                case .spool: spoolRows
                case .archive: archiveRows
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
        .animation(.easeInOut(duration: Theme.AnimationDuration.standard), value: feedSource)
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

    /// Editorial one-liner above the feed — gives each source a touch
    /// of identity without changing the layout. Hidden in search mode
    /// (the search bar provides its own context) and on sources where
    /// `FeedDescriptions` returns nil.
    @ViewBuilder
    private var feedSubtitleRow: some View {
        if let subtitle = FeedDescriptions.subtitle(for: feedSource) {
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .padding(.bottom, 10)
                .listRowBackground(Color(.systemBackground))
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private var feedRows: some View {
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
                StoryListLoadingStateView(text: "Loading \(viewModel.feed.title.lowercased())…")
            }
        } else {
            let filtered = filteredStories(viewModel.stories)
            let hasMore = viewModel.stories.count < viewModel.totalAvailable

            ForEach(filtered, id: \.id) { story in
                storyRow(story: story)
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
                StoryListLoadingStateView(text: "Computing trends…")
            }
        } else if trending.items.isEmpty {
            statusRow {
                ContentUnavailableView {
                    Label("Trending is still warming up", systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text("Trending is computed on your device from score changes between visits — there's no data to compare yet. Open Top a few times over a few hours and stories climbing fastest will surface here.")
                        .multilineTextAlignment(.center)
                } actions: {
                    Button {
                        switchSource(to: .category(.top))
                    } label: {
                        Text("Open Top")
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
                }
            }
        } else {
            ForEach(filteredStories(trending.items), id: \.id) { story in
                storyRow(story: story, context: trending.contextLine(for: story))
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
                StoryListLoadingStateView(text: "Loading…")
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
            let filtered = filteredStories(browse.results)

            ForEach(filtered, id: \.id) { story in
                storyRow(story: story)
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
                    "No saved stories yet",
                    systemImage: "bookmark",
                    description: Text("Bookmark anything worth coming back to.")
                )
            }
        } else {
            ForEach(savedStories, id: \.id) { item in
                storyRow(
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
            statusRow { StoryListLoadingStateView(text: "Loading Following…") }
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
                storyRow(story: story, context: "by \(story.by ?? "—")")
            }
        }
    }

    @ViewBuilder
    private var spoolRows: some View {
        if spool.isEmpty {
            statusRow {
                ContentUnavailableView(
                    "Your spool is empty",
                    systemImage: "headphones",
                    description: Text("Add stories throughout the day and listen later.")
                )
            }
        } else {
            playAllCard
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 12, trailing: 18))
                .selectionDisabled()

            ForEach(spool, id: \.id) { item in
                spoolPlaylistRow(item: item)
            }
            .onMove(perform: moveSpool)
        }
    }

    /// Upgrade path: rows that existed before we added `position`
    /// all land with position = 0 by SwiftData's default-value
    /// migration. That makes the @Query sort ambiguous and renders
    /// the queue in arbitrary order. On every launch, check
    /// whether more than one row shares position 0 — if so,
    /// backfill positions in queuedAt-newest-first order so the
    /// queue matches what the user remembers.
    private func backfillSpoolPositionsIfNeeded() {
        let zeroes = spool.filter { $0.position == 0 }
        guard zeroes.count > 1 else { return }
        let sorted = spool.sorted { lhs, rhs in
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
    private func moveSpool(from source: IndexSet, to destination: Int) {
        var stories = spool
        stories.move(fromOffsets: source, toOffset: destination)
        for (index, story) in stories.enumerated() {
            story.position = index
        }
    }

    /// Top-of-queue card — "Play All" pill + queue-level totals.
    /// When the player is already running, the same card swaps to
    /// a "Now Playing" surface showing the current item's title +
    /// position. Tap toggles play/pause.
    @ViewBuilder
    private var playAllCard: some View {
        let totalSeconds = spool.reduce(0) { $0 + $1.estimatedDurationSeconds }
        let isPlayingThisQueue = spoolPlayer.isActive &&
            spoolPlayer.queue.map(\.id) == spool.map(\.id)
        // Preparing: handlePlayAllTap stashed a pendingPlayStoryID,
        // SummaryPrefetcher is racing to land the first item's
        // script, and we're waiting on the .onChange handler to
        // auto-start. Without this state the button looked dead.
        let isPreparing = pendingPlayStoryID != nil && !isPlayingThisQueue
        let pendingReadyCount = spool.filter { $0.playlistScript != nil }.count
        let audioReadyCount = spool.filter { $0.cachedAudioGeneratedAt != nil }.count
        let pendingTotal = spool.count
        let audioPending = pendingTotal > 0 && audioReadyCount < pendingTotal

        Button {
            handlePlayAllTap()
        } label: {
            HStack(spacing: 12) {
                if isPreparing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.accent)
                        .frame(width: 24)
                } else {
                    Image(systemName: playAllIconName(isPlaying: isPlayingThisQueue))
                        .font(.title2)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 24)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(isPreparing
                            ? "Preparing…"
                            : (isPlayingThisQueue ? "Now Playing" : "Play All"))
                        .font(.headline)
                        .contentTransition(.numericText())
                    Text(playAllSubtitle(totalSeconds: totalSeconds,
                                          isPlayingThisQueue: isPlayingThisQueue,
                                          isPreparing: isPreparing,
                                          readyCount: pendingReadyCount,
                                          audioReadyCount: audioReadyCount,
                                          audioPending: audioPending,
                                          totalCount: pendingTotal))
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
        .disabled(isPreparing)
        .accessibilityHint("Plays the article and discussion summary for each queued story.")
    }

    private func playAllIconName(isPlaying: Bool) -> String {
        if isPlaying {
            return spoolPlayer.state == .playing ? "pause.fill" : "play.fill"
        }
        return "play.fill"
    }

    private func playAllSubtitle(
        totalSeconds: Int,
        isPlayingThisQueue: Bool,
        isPreparing: Bool,
        readyCount: Int,
        audioReadyCount: Int,
        audioPending: Bool,
        totalCount: Int
    ) -> String {
        if isPreparing {
            return "Generating summaries · \(readyCount) of \(totalCount) ready"
        }
        if isPlayingThisQueue, let current = spoolPlayer.currentItem {
            return current.title
        }
        // While audio is rendering in the background, show the
        // running count so the user sees the queue catching up.
        // Falls through to the static "N stories · ~M min" line
        // once every item has its audio cached.
        if audioPending {
            return "Rendering audio · \(audioReadyCount) of \(totalCount) ready"
        }
        let count = spool.count
        let mins = max(1, totalSeconds / 60)
        return "\(count) \(count == 1 ? "story" : "stories") · ~\(mins) min listen"
    }

    // MARK: - Archive

    @ViewBuilder
    private var archiveRows: some View {
        if archive.isEmpty {
            statusRow {
                ContentUnavailableView {
                    Label("Nothing archived yet", systemImage: "archivebox")
                } description: {
                    Text("Stories you've listened to will land here.")
                } actions: {
                    // ContentUnavailableView's action area gives buttons
                    // its own rendering; pairing it with `.buttonStyle(.glass)`
                    // on iOS 26 collapses the Label down to a tall icon-only
                    // capsule. Using the system-default style with `Text`
                    // gets us a clean prominent action that respects the
                    // surrounding layout.
                    Button {
                        switchSource(to: .spool)
                    } label: {
                        Text("Go to Spool")
                    }
                    .tint(Theme.accent)
                }
            }
        } else {
            ForEach(archive, id: \.id) { item in
                StoryRowView(
                    story: item.asHNItem,
                    context: item.archivedAt.map { "Archived \($0.formatted(.relative(presentation: .named)))" } ?? "Archived",
                    isRead: readIDs.contains(item.id),
                    isSaved: savedIDs.contains(item.id),
                    isSelected: selectedStory?.id == item.id
                )
                .tag(item.asHNItem)
                .listRowBackground(rowBackground(for: item.asHNItem))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        // Drop player reference first if it's still
                        // holding this @Model (e.g., the user archived
                        // mid-playback and is now deleting from the
                        // archive view) — same crash class as the
                        // active-spool swipe-delete.
                        if spoolPlayer.queue.contains(where: { $0.id == item.id }) {
                            spoolPlayer.stop()
                        }
                        modelContext.delete(item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        // Restore: clear the archive flag and put the
                        // row back at the top of the spool. SwiftData
                        // @Query for `spool` filters on archivedAt so
                        // the row reappears immediately.
                        //
                        // Fetch min-position fresh from modelContext
                        // (not from the @Query snapshot) so two rapid
                        // restores can't both land on the same value.
                        item.archivedAt = nil
                        var descriptor = FetchDescriptor<SpooledStory>(
                            predicate: #Predicate { $0.archivedAt == nil },
                            sortBy: [SortDescriptor(\.position)]
                        )
                        descriptor.fetchLimit = 1
                        let minPosition = (try? modelContext.fetch(descriptor).first?.position) ?? 0
                        item.position = minPosition - 1
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    .tint(.purple)
                }
            }
        }
    }

    /// Spool playlist row — just the story row with a faint accent
    /// highlight on whichever item the player is currently reading.
    /// No per-row play button; the spool is driven by the Play All
    /// card at the top, drag-to-reorder, and swipe-to-delete.
    @ViewBuilder
    private func spoolPlaylistRow(item: SpooledStory) -> some View {
        let isCurrent = spoolPlayer.currentItem?.id == item.id
        let summaryReady = item.playlistScript != nil
        let audioReady = item.cachedAudioGeneratedAt != nil
        // Tri-state row context: no summary yet, summary ready but
        // audio still rendering, or fully ready. The audio render
        // is the user-visible bottleneck — surface it so they can
        // see progress, not just an inert "preparing" label.
        let context: String = {
            if !summaryReady { return "Preparing summary…" }
            if !audioReady   { return "Rendering audio…" }
            return "Ready to play"
        }()
        // Tap is allowed once the summary lands — the player will
        // play from the cached file if audio is ready, otherwise
        // fall through to the live-synth path.
        let canPlay = summaryReady

        // Tapping a spool row should drop the user straight into
        // playback — not the article-detail screen the other feeds
        // use. The queue is "things I want to hear right now", so the
        // primary action on a row is "play this one and open the
        // now-playing surface". Wrapping in a Button (rather than
        // relying on List's tag-based selection) lets us bypass the
        // selection plumbing entirely.
        Button {
            handleSpoolRowTap(item: item)
        } label: {
            StoryRowView(
                story: item.asHNItem,
                context: context,
                isRead: readIDs.contains(item.id),
                isSaved: savedIDs.contains(item.id)
            )
            .opacity(canPlay ? 1.0 : 0.7)
            .padding(.vertical, 2)
            .background(
                isCurrent
                    ? Theme.accent.opacity(Theme.Opacity.nowPlayingRow)
                    : Color.clear,
                in: .rect(cornerRadius: Theme.CornerRadius.medium, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canPlay)
        // Trailing-edge buttons appear right-to-left in declaration
        // order. Delete is the explicit destructive tap; Archive is
        // the trailing-most button and so is the full-swipe target —
        // safer default since the user can restore from the archive.
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                // If the player is mid-playback on this item (or has it
                // in its queue snapshot), stop first so it drops its
                // strong reference to the @Model instance before we
                // delete it — touching properties of a deleted SwiftData
                // object throws/crashes.
                if spoolPlayer.queue.contains(where: { $0.id == item.id }) {
                    spoolPlayer.stop()
                }
                modelContext.delete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                item.archivedAt = .now
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(.purple)
        }
    }

    /// Tap handler for a row inside the Spool queue. Starts the
    /// player at this item's index (preserving the rest of the queue
    /// behind it) and presents the now-playing sheet.
    private func handleSpoolRowTap(item: SpooledStory) {
        guard let index = spool.firstIndex(where: { $0.id == item.id }) else { return }
        // If we're already playing this exact queue, just jump to
        // the tapped item rather than restarting from scratch.
        let sameQueue = spoolPlayer.queue.map(\.id) == spool.map(\.id)
        if sameQueue, spoolPlayer.isActive {
            if spoolPlayer.currentItem?.id != item.id {
                // Jump to the tapped item. SpoolPlayer doesn't have a
                // public "jump to index" so we restart with the same
                // items but a new starting index.
                spoolPlayer.play(items: Array(spool), startingAt: index)
            }
        } else {
            spoolPlayer.play(items: Array(spool), startingAt: index)
        }
        showNowPlaying = true
    }

    /// Play All handler. If everything in the queue already has a
    /// script, starts immediately. If the first item needs a
    /// prefetch, kicks one off + stashes pendingPlayStoryID so the
    /// auto-start fires as soon as that first item is ready.
    private func handlePlayAllTap() {
        let isPlayingThisQueue = spoolPlayer.isActive &&
            spoolPlayer.queue.map(\.id) == spool.map(\.id)
        if isPlayingThisQueue {
            // Active queue: surface the now-playing sheet so the
            // user can scrub / inspect what's playing rather than
            // toggling play/pause from a button they probably
            // pressed to dive in, not stop.
            showNowPlaying = true
            return
        }
        guard let first = spool.first else { return }
        if first.playlistScript != nil {
            pendingPlayStoryID = nil
            spoolPlayer.play(items: spool)
            showNowPlaying = true
            return
        }
        // Schedule prefetch for every item missing summaries so
        // the playlist can stream through without stalling on
        // each row.
        for item in spool where item.cachedArticleSummary == nil {
            SummaryPrefetcher.schedulePrefetch(for: item, in: modelContext)
        }
        pendingPlayStoryID = first.id
    }

    // MARK: - Mentions

    @ViewBuilder
    private var mentionsRows: some View {
        if !auth.isLoggedIn {
            statusRow {
                ContentUnavailableView {
                    Label("Sign In for Mentions", systemImage: "at")
                } description: {
                    Text("Sign in to your Hacker News account to see replies to your comments.")
                } actions: {
                    Button {
                        showLogin = true
                    } label: {
                        Text("Sign In")
                    }
                    .tint(Theme.accent)
                }
            }
        } else if mentions.items.isEmpty && (mentions.isLoading || switchingFeed) {
            statusRow { StoryListLoadingStateView(text: "Loading Mentions…") }
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
            // SeenMention.id is .unique — guard against duplicate
            // insert when the user opens the same mention twice
            // rapidly (the @Query snapshot may not yet reflect a
            // very recent insert).
            let replyID = record.reply.id
            if !mentionSeenIDs.contains(replyID) {
                let descriptor = FetchDescriptor<SeenMention>(
                    predicate: #Predicate { $0.id == replyID }
                )
                if (try? modelContext.fetch(descriptor).first) == nil {
                    modelContext.insert(SeenMention(id: replyID))
                }
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
        case .saved, .spool, .archive:
            return ""
        }
    }

    /// The shared menu content used by both the big hero selector and
    /// the small inline navbar selector. Sectioned so the user can jump
    /// to any feed (Categories), curated view (Browse), or library
    /// (Saved / Spool) from a single tap on the title. Every entry
    /// flips `feedSource`, populating the same list scaffolding below —
    /// no modals.
    @ViewBuilder
    private var feedMenuContent: some View {
        // Same visibility filter as the sidebar's Categories
        // section. Hidden feeds disappear from the toolbar picker
        // too — otherwise the user would still see them here and
        // wonder why the sidebar dropped them.
        let visibleCategories = HNStoryFeed.visible(hiddenRaw: hiddenFeedsRaw)
        if !visibleCategories.isEmpty {
            Section("Categories") {
                ForEach(visibleCategories) { feed in
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
            // Spool removed — the dedicated headphones toolbar
            // button + the prominent sidebar section already
            // surface it. Duplicating in the picker menu adds
            // clutter without giving the user a new path.
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
    private func storyRow(story: HNItem, context: String? = nil) -> some View {
        StoryRowView(
            story: story,
            context: context,
            isRead: readIDs.contains(story.id),
            isSaved: savedIDs.contains(story.id),
            isSpooled: spooledIDs.contains(story.id),
            isSelected: selectedStory?.id == story.id,
            suppressTypeBadge: dedicatedKindFeed,
            hideRawScore: feedSource == .trending
        )
        .tag(story)
        .listRowBackground(rowBackground(for: story))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                toggleSaved(story)
            } label: {
                Label(savedIDs.contains(story.id) ? "Unsave" : "Save", systemImage: "bookmark.fill")
            }
            .tint(Theme.accent)

            Button {
                toggleSpool(story)
            } label: {
                Label(
                    spooledIDs.contains(story.id) ? "Remove" : "Spool",
                    systemImage: spooledIDs.contains(story.id) ? "minus.circle.fill" : "headphones"
                )
            }
            .tint(.purple)

            if let url = story.url.flatMap(URL.init(string:)) {
                ShareLink(item: url, preview: SharePreview(story.title ?? "Spool story")) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .tint(.blue)
            }
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

    private func toggleSpool(_ story: HNItem) {
        if let existing = spool.first(where: { $0.id == story.id }) {
            modelContext.delete(existing)
        } else {
            // Fetch the live max position from modelContext, not from
            // the @Query snapshot — @Query updates on the next SwiftUI
            // pass, so two rapid toggles would both read the stale max
            // and collide on the same position value.
            var descriptor = FetchDescriptor<SpooledStory>(
                sortBy: [SortDescriptor(\.position, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            let maxPosition = (try? modelContext.fetch(descriptor).first?.position) ?? -1
            let queued = SpooledStory(
                id: story.id,
                title: story.title ?? "(untitled)",
                urlString: story.url,
                author: story.by,
                score: story.score,
                descendants: story.descendants,
                position: maxPosition + 1
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
                StoryListLoadingStateView(text: "Searching…")
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

            ForEach(search.results, id: \.id) { story in
                storyRow(story: story)
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

    /// Force every row's background to the system background.
    /// Why: List's `.tag(_:)` + selection binding triggers iOS's
    /// auto-styling for selected rows on iPad — strong accent tint
    /// PLUS inverted (white) text color. Even with a soft custom
    /// tint, the text stays inverted, leaving white-on-pale-orange
    /// titles you can barely read. By overriding listRowBackground
    /// to a flat color we disable iOS's selection chrome entirely;
    /// the actual "this is selected" visual is drawn INSIDE the
    /// row (`StoryRowView.isSelected`), where we control the text
    /// color end-to-end.
    private func rowBackground(for story: HNItem) -> Color {
        Color(.systemBackground)
    }

    /// True when the active feed is already a single-kind category
    /// (Ask HN / Show HN / Jobs). Every row in those feeds is the
    /// same kind and the title already carries the same prefix, so
    /// the per-row "ASK" / "SHOW" / "JOB" pill is redundant.
    private var dedicatedKindFeed: Bool {
        guard case let .category(feed) = feedSource else { return false }
        switch feed {
        case .ask, .show, .job: return true
        default: return false
        }
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

// Helpers (LoadingStateView, SidebarToggleButton, ConditionalSearchable)
// moved to StoryListView+Helpers.swift to keep this file's surface
// area focused on the routing + row composition logic.

#Preview {
    StoryListView()
        .modelContainer(
            for: [
                SavedStory.self,
                ReadStory.self,
                SpooledStory.self,
                ScoreSnapshot.self,
                FollowedUser.self,
                SeenMention.self,
            ],
            inMemory: true
        )
        .environmentObject(AuthViewModel())
        .environmentObject(AppRouter())
}
