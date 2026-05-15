import SwiftUI
import SwiftData

/// The leading column of the unified NavigationSplitView. On iPhone the
/// user reaches it via edge-swipe or the sidebar toolbar button; on iPad
/// it's the always-visible left column. Same content either way:
/// account, category picker, library, post, about.
struct AppSidebar: View {
    @ObservedObject var viewModel: StoryListViewModel
    @EnvironmentObject private var auth: AuthViewModel
    @Query private var savedStories: [SavedStory]
    @State private var profileTarget: String?

    let onSignIn: () -> Void
    let onSignOut: () -> Void
    let onSubmit: () -> Void
    let onSaved: () -> Void
    /// Set on compact width; lets the user swipe left to return to the
    /// content column. `nil` when running as a regular-width split where
    /// the sidebar is permanent.
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        List {
            accountSection
            categoriesSection
            librarySection
            if auth.isLoggedIn {
                postSection
            }
            aboutSection
        }
        .listStyle(.sidebar)
        .navigationTitle("HN Skim")
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        .sheet(item: Binding(
            get: { profileTarget.map(SidebarUsername.init) },
            set: { profileTarget = $0?.value }
        )) { target in
            UserProfileView(username: target.value)
        }
        .simultaneousGesture(dismissSwipe)
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
                Button {
                    if feed != viewModel.feed {
                        viewModel.feed = feed
                    }
                } label: {
                    HStack {
                        Label(feed.navigationTitle, systemImage: feed.icon)
                            .foregroundStyle(.primary)
                        Spacer()
                        if feed == viewModel.feed {
                            Image(systemName: "checkmark")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var librarySection: some View {
        Section("Reading List") {
            Button(action: onSaved) {
                HStack {
                    Label("Saved Stories", systemImage: "bookmark")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(savedStories.count.formatted())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
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
            HStack {
                Text("Version")
                Spacer()
                Text(Self.versionString)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
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
