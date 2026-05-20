import SwiftUI
import SwiftData

/// The leading column of the unified NavigationSplitView. Feed rows
/// are tagged with their MainFeedSource and participate in the
/// List's selection binding — that's what makes
/// NavigationSplitView auto-push the content column on compact
/// width when the user taps. Sign-in / submit / about / settings
/// rows stay as plain Buttons since they fire actions rather than
/// changing the selected feed.
struct AppSidebar: View {
    @Binding var selection: MainFeedSource?
    @EnvironmentObject private var auth: AuthViewModel
    /// iPad uses three columns (regular); iPhone collapses to a
    /// NavigationStack rooted at the sidebar (compact). The custom
    /// sidebar-visibility toggle only makes sense when there's a
    /// sidebar that can actually be shown/hidden.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(SettingsKeys.hiddenFeeds) private var hiddenFeedsRaw: String = ""
    @Query private var savedStories: [SavedStory]
    @Query(filter: #Predicate<SpooledStory> { $0.archivedAt == nil })
    private var spool: [SpooledStory]
    @Query(filter: #Predicate<SpooledStory> { $0.archivedAt != nil })
    private var archive: [SpooledStory]
    @Query private var followedUsers: [FollowedUser]
    @State private var profileTarget: String?
    @State private var showAbout: Bool = false
    @State private var showSettings: Bool = false

    let onSignIn: () -> Void
    let onSignOut: () -> Void
    let onSubmit: () -> Void
    /// Optional handler invoked when the user taps the custom
    /// leading sidebar-visibility toggle. Wired by the parent so it
    /// can flip its `NavigationSplitViewVisibility` binding.
    var onToggleSidebar: (() -> Void)? = nil

    var body: some View {
        List(selection: $selection) {
            accountSection
            // Post sits right under the account when the user is
            // signed in — it's the primary signed-in action, so
            // putting it within thumb's reach beats burying it
            // under Library or Settings.
            if auth.isLoggedIn {
                postSection
            }
            // Spool sits high in the sidebar — it's the headline
            // feature, and most users want one tap to their queue,
            // not a scroll past Categories + Browse to find it.
            listenSection
            categoriesSection
            browseSection
            librarySection
            settingsSection
            aboutSection
        }
        .listStyle(.sidebar)
        .navigationTitle("Spool")
        // iPad-only: relocate the sidebar-visibility toggle to the
        // leading edge so it sits on the same side our other
        // toolbars open from. On iPhone the sidebar IS the root of
        // the NavigationStack — there's nothing to hide — and we
        // avoid `.toolbar(removing: .sidebarToggle)` there entirely
        // (applying it on iPhone disturbs `.tint` propagation into
        // the sidebar's row icons).
        .ifPad(horizontalSizeClass) { content in
            content
                .toolbar(removing: .sidebarToggle)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            onToggleSidebar?()
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                        .accessibilityLabel("Hide Sidebar")
                    }
                }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        .sheet(item: Binding(
            get: { profileTarget.map(SidebarUsername.init) },
            set: { profileTarget = $0?.value }
        )) { target in
            UserProfileView(username: target.value)
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(auth)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var accountSection: some View {
        Section("Account") {
            if auth.isLoggedIn {
                Button {
                    if let username = auth.username {
                        profileTarget = username
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(auth.username ?? "Signed in")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("View profile & activity")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
                .disabled(auth.username == nil)

                Button(role: .destructive, action: onSignOut) {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } else {
                Button(action: onSignIn) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sign In")
                                .foregroundStyle(.primary)
                            Text("Vote, post, and reply.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "person.circle")
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var categoriesSection: some View {
        // Filtered by Settings → Display → Visible Categories.
        // When the user hides every category, the section
        // collapses entirely rather than rendering an empty
        // header — they can re-show one from Settings.
        let visible = HNStoryFeed.visible(hiddenRaw: hiddenFeedsRaw)
        if !visible.isEmpty {
            Section("Categories") {
                ForEach(visible) { feed in
                    Label(feed.navigationTitle, systemImage: feed.icon)
                        .tag(MainFeedSource.category(feed))
                }
            }
        }
    }

    @ViewBuilder
    private var browseSection: some View {
        Section("Browse") {
            Label("Trending", systemImage: "chart.line.uptrend.xyaxis")
                .tag(MainFeedSource.trending)
            ForEach(BestOfWindow.allCases) { window in
                Label("Best of \(window.title)", systemImage: window.icon)
                    .tag(MainFeedSource.bestOf(window))
            }
        }
    }

    /// Spool has its own top-level section — sibling to Categories
    /// and Browse — because it's the headline feature: the queue of
    /// stories with cached AI summaries you can read or hear.
    @ViewBuilder
    private var listenSection: some View {
        Section("Spool") {
            Label("Queue", systemImage: "headphones")
                .badge(spool.count)
                .tag(MainFeedSource.spool)
            Label("Archive", systemImage: "archivebox")
                .badge(archive.count)
                .tag(MainFeedSource.archive)
        }
    }

    @ViewBuilder
    private var librarySection: some View {
        Section("Library") {
            Label("Saved", systemImage: "bookmark")
                .badge(savedStories.count)
                .tag(MainFeedSource.saved)
            if !followedUsers.isEmpty {
                Label("Following", systemImage: "person.2")
                    .badge(followedUsers.count)
                    .tag(MainFeedSource.following)
            }
            if auth.isLoggedIn {
                Label("Mentions", systemImage: "at")
                    .tag(MainFeedSource.mentions)
            }
        }
    }

    /// Single sidebar row that opens the Settings sheet. Everything
    /// previously inline (toggles, stepper, notification test rows,
    /// mark-all-unread) lives in `SettingsView` now — the sidebar
    /// should be destinations, not configuration.
    @ViewBuilder
    private var settingsSection: some View {
        Section {
            Button {
                showSettings = true
            } label: {
                HStack {
                    Label("Settings", systemImage: "gear")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var postSection: some View {
        Section("Post") {
            Button(action: onSubmit) {
                Label("New Submission", systemImage: "square.and.pencil")
                    .foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section("About") {
            Button {
                showAbout = true
            } label: {
                HStack {
                    // Section header is already "About", so the row
                    // label is just the product name to avoid the
                    // redundant "About > About Spool".
                    Label("Spool", systemImage: "info.circle")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(Self.versionString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

/// Lets `sheet(item:)` use a plain String username.
private struct SidebarUsername: Identifiable {
    let value: String
    var id: String { value }
}

/// Conditionally applies `transform` only when the size class is
/// `.regular` (i.e., iPad). Keeps iPhone's sidebar chrome
/// completely untouched — important because `.toolbar(removing:
/// .sidebarToggle)` on iPhone has been observed to disrupt
/// `.tint` propagation into the sidebar's row icons.
extension View {
    @ViewBuilder
    func ifPad<T: View>(
        _ sizeClass: UserInterfaceSizeClass?,
        @ViewBuilder _ transform: (Self) -> T
    ) -> some View {
        if sizeClass == .regular {
            transform(self)
        } else {
            self
        }
    }
}
