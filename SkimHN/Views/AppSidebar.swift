import SwiftUI
import SwiftData

/// The leading column of the unified NavigationSplitView. On iPhone the
/// user reaches it via edge-swipe or the sidebar toolbar button; on iPad
/// it's the always-visible left column. Every selection flows through a
/// single `onSelect(MainFeedSource)` callback so the main list can
/// react uniformly — no per-section sheet plumbing.
struct AppSidebar: View {
    let activeSource: MainFeedSource
    @EnvironmentObject private var auth: AuthViewModel
    @Query private var savedStories: [SavedStory]
    @Query private var readLaterStories: [ReadLaterStory]
    @Query private var followedUsers: [FollowedUser]
    @State private var profileTarget: String?
    @State private var showAbout: Bool = false
    @AppStorage(SettingsKeys.showThumbnails) private var showThumbnails: Bool = true
    @AppStorage(SettingsKeys.hideReadStories) private var hideReadStories: Bool = false
    @AppStorage(SettingsKeys.minStoryComments) private var minStoryComments: Int = 0

    /// One-shot result UI for the "Send Test Notification" row.
    /// Auto-resets to .idle ~6 seconds after a successful schedule
    /// (just past the 5s trigger) so the checkmark doesn't linger
    /// forever.
    enum NotifierStatus: Equatable {
        case idle
        case scheduled
        case denied(String)
    }
    @State private var notifierStatus: NotifierStatus = .idle
    /// Last "Test BG Refresh" outcome. nil before first tap.
    @State private var bgRefreshOutcome: MentionsNotifier.CheckOutcome?

    let onSignIn: () -> Void
    let onSignOut: () -> Void
    let onSubmit: () -> Void
    /// Routes every list-source pick (categories, browse, library)
    /// through one handler. The owner is expected to flip its own
    /// `feedSource` state.
    let onSelect: (MainFeedSource) -> Void
    /// Set on compact width; lets the user swipe left to return to the
    /// content column. `nil` when running as a regular-width split where
    /// the sidebar is permanent.
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        List {
            accountSection
            categoriesSection
            browseSection
            librarySection
            if auth.isLoggedIn {
                postSection
            }
            settingsSection
            aboutSection
        }
        .listStyle(.sidebar)
        .navigationTitle("SkimHN")
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        .sheet(item: Binding(
            get: { profileTarget.map(SidebarUsername.init) },
            set: { profileTarget = $0?.value }
        )) { target in
            UserProfileView(username: target.value)
        }
        .simultaneousGesture(dismissSwipe)
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
    }

    /// Leftward drag dismisses the sidebar on compact width. Uses
    /// `simultaneousGesture` so List's vertical scroll keeps working.
    private var dismissSwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                guard let onDismiss else { return }
                let mostlyHorizontal = abs(value.translation.width) > abs(value.translation.height)
                let movedLeftward = value.translation.width < -60
                if mostlyHorizontal && movedLeftward {
                    onDismiss()
                }
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
        Section("Categories") {
            ForEach(HNStoryFeed.allCases) { feed in
                sidebarRow(
                    label: feed.navigationTitle,
                    icon: feed.icon,
                    isActive: activeSource == .category(feed)
                ) {
                    onSelect(.category(feed))
                }
            }
        }
    }

    @ViewBuilder
    private var browseSection: some View {
        Section("Browse") {
            sidebarRow(
                label: "Trending",
                icon: "chart.line.uptrend.xyaxis",
                isActive: activeSource == .trending
            ) {
                onSelect(.trending)
            }
            ForEach(BestOfWindow.allCases) { window in
                sidebarRow(
                    label: "Best of \(window.title)",
                    icon: window.icon,
                    isActive: activeSource == .bestOf(window)
                ) {
                    onSelect(.bestOf(window))
                }
            }
        }
    }

    @ViewBuilder
    private var librarySection: some View {
        Section("Library") {
            sidebarRow(
                label: "Saved",
                icon: "bookmark",
                isActive: activeSource == .saved,
                trailingCount: savedStories.count
            ) {
                onSelect(.saved)
            }
            sidebarRow(
                label: "Read Later",
                icon: "tray",
                isActive: activeSource == .readLater,
                trailingCount: readLaterStories.count
            ) {
                onSelect(.readLater)
            }
            if !followedUsers.isEmpty {
                sidebarRow(
                    label: "Following",
                    icon: "person.2",
                    isActive: activeSource == .following,
                    trailingCount: followedUsers.count
                ) {
                    onSelect(.following)
                }
            }
            if auth.isLoggedIn {
                sidebarRow(
                    label: "Mentions",
                    icon: "at",
                    isActive: activeSource == .mentions,
                    trailingCount: nil
                ) {
                    onSelect(.mentions)
                }
            }
        }
    }

    @ViewBuilder
    private var settingsSection: some View {
        Section("Settings") {
            Toggle(isOn: $showThumbnails) {
                Label("Show Thumbnails", systemImage: "photo")
                    .foregroundStyle(.primary)
            }
            .tint(Theme.accent)

            Toggle(isOn: $hideReadStories) {
                Label("Hide Read Stories", systemImage: "eye.slash")
                    .foregroundStyle(.primary)
            }
            .tint(Theme.accent)

            Stepper(value: $minStoryComments, in: 0...100, step: 5) {
                Label {
                    HStack {
                        Text("Minimum Comments")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(minStoryComments == 0 ? "Off" : "\(minStoryComments)+")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText(value: Double(minStoryComments)))
                    }
                } icon: {
                    Image(systemName: "bubble.left.and.bubble.right")
                }
            }
            .tint(Theme.accent)

            if auth.isLoggedIn {
                mentionNotificationTestRow
                mentionBGRefreshTestRow
            }
        }
    }

    /// Schedules a representative UN notification 5 seconds out so
    /// the user can lock the device / switch apps and see what the
    /// real lock-screen experience will look like.
    @ViewBuilder
    private var mentionNotificationTestRow: some View {
        Button {
            Task {
                do {
                    try await MentionsNotifier.sendTestNotification()
                    notifierStatus = .scheduled
                    // Clear the indicator a beat after the trigger
                    // fires so the row doesn't keep claiming
                    // "scheduled" hours later.
                    try? await Task.sleep(for: .seconds(6))
                    if notifierStatus == .scheduled {
                        notifierStatus = .idle
                    }
                } catch {
                    notifierStatus = .denied(error.localizedDescription)
                }
            }
        } label: {
            Label {
                HStack {
                    Text("Send Test Notification")
                        .foregroundStyle(.primary)
                    Spacer()
                    notifierTrailing
                }
            } icon: {
                Image(systemName: "bell.badge")
            }
        }
    }

    /// Runs the same fetch-and-notify pipeline the background task
    /// runs, in-app. Lets the user confirm the actual mentions check
    /// end-to-end without waiting for iOS to schedule a real BG slot
    /// (which can take hours).
    @ViewBuilder
    private var mentionBGRefreshTestRow: some View {
        Button {
            Task {
                bgRefreshOutcome = await MentionsNotifier.runMentionsCheckAndNotify(
                    username: auth.username
                )
            }
        } label: {
            Label {
                HStack {
                    Text("Test BG Refresh Now")
                        .foregroundStyle(.primary)
                    Spacer()
                    bgRefreshTrailing
                }
            } icon: {
                Image(systemName: "arrow.clockwise.circle")
            }
        }
    }

    @ViewBuilder
    private var notifierTrailing: some View {
        switch notifierStatus {
        case .idle:
            EmptyView()
        case .scheduled:
            Label("In 5s", systemImage: "checkmark")
                .labelStyle(.titleAndIcon)
                .font(.footnote)
                .foregroundStyle(Theme.accent)
        case .denied(let message):
            Text(message)
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(2)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var bgRefreshTrailing: some View {
        switch bgRefreshOutcome {
        case .none:
            EmptyView()
        case .noUsername:
            Text("Sign in first")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .notificationsDenied:
            Text("Notifications off")
                .font(.footnote)
                .foregroundStyle(.red)
        case .failed:
            Text("Failed")
                .font(.footnote)
                .foregroundStyle(.red)
        case .skippedFirstRun(let seeded):
            Text("Seeded \(seeded)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        case .fired(let count):
            Text(count == 0 ? "No new mentions" : "\(count) fired")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
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
                    Label("About SkimHN", systemImage: "info.circle")
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

    /// Shared row layout for every selectable sidebar entry — checkmark
    /// on the trailing edge when the source matches, optional count for
    /// library rows.
    @ViewBuilder
    private func sidebarRow(
        label: String,
        icon: String,
        isActive: Bool,
        trailingCount: Int? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(label, systemImage: icon)
                    .foregroundStyle(.primary)
                Spacer()
                if let trailingCount {
                    Text(trailingCount.formatted())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.accent)
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
