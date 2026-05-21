import SwiftUI
import SwiftData
import CoreSpotlight
import BackgroundTasks

@main
struct SpoolApp: App {
    @StateObject private var auth = AuthViewModel()
    @StateObject private var router = AppRouter()
    /// Cross-screen Spool playlist controller. Held at the
    /// scene root so the mini player overlay and the playlist
    /// screen share the same controller instance.
    @StateObject private var spoolPlayer = SpoolPlayer()
    /// `true` for the first ~1.2s of process lifetime, then false for
    /// the rest of the session. Drives the branded splash overlay.
    @State private var showLaunch: Bool = true
    /// Observed so we can reschedule the Mentions background refresh
    /// every time the app moves to background. iOS only honors the
    /// most recently submitted request per identifier.
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Two distinct nav-bar appearances:
        //
        //   - scrollEdge → transparent. The large title floats over
        //     the content; iOS reveals the `.searchable` field
        //     beneath the title naturally. Previously we forced a
        //     materialized background here, which broke the search
        //     bar's reveal behavior — it stopped showing entirely.
        //
        //   - standard / compact → default material. Kicks in as
        //     soon as content slides under the bar.
        //
        // Modern editorial title — meaningfully larger, ultraLight
        // weight, mild kerning. Applied to both appearances so the
        // title rendering doesn't flicker on the scroll transition.
        // Editorial largeTitle — `.thin` weight + slight kerning gives
        // a refined feel without the rendering issues that come with
        // `.ultraLight`. Stays at the system default point size so the
        // navbar's reserved frame contains the glyphs cleanly.
        let titleDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle)
        let titleFont = UIFont.systemFont(
            ofSize: titleDescriptor.pointSize,
            weight: .thin
        )
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .kern: 0.3,
        ]

        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        scrollEdge.largeTitleTextAttributes = titleAttrs

        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        scrolled.largeTitleTextAttributes = titleAttrs

        UINavigationBar.appearance().scrollEdgeAppearance = scrollEdge
        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().compactAppearance = scrolled

        // Register the BGAppRefreshTask handler. MUST happen during
        // app launch (before `applicationDidFinishLaunching` returns)
        // or iOS rejects every subsequent submit() call for this
        // identifier — meaning the Mentions feature would never run
        // in the background.
        registerMentionsBackgroundTask()
    }

    private func registerMentionsBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: MentionsNotifier.taskIdentifier,
            using: nil
        ) { task in
            // Schedule the next run immediately so iOS has a request
            // queued for the next opportunity, even if this run fails
            // or times out.
            MentionsNotifier.scheduleNextRefresh()

            let username = UserDefaults.standard.string(forKey: "hn.user")
            let work = Task {
                _ = await MentionsNotifier.runMentionsCheckAndNotify(username: username)
                task.setTaskCompleted(success: true)
            }
            // iOS hands the BG task ~30 s. If we exceed, the system
            // tears us down and would otherwise call setTaskCompleted
            // for us with success: false — pre-empt by cancelling our
            // own work so partial state stays consistent.
            task.expirationHandler = {
                work.cancel()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                StoryListView()
                    .environmentObject(auth)
                    .environmentObject(router)
                    .environmentObject(spoolPlayer)
                    .tint(Theme.accent)
                    // Mini player overlay — sits as a safe-area inset
                    // at the bottom across every screen, the same
                    // placement Music / Podcasts use.
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        SpoolMiniPlayer()
                            .environmentObject(spoolPlayer)
                    }
                    .animation(.easeInOut(duration: Theme.AnimationDuration.fast), value: spoolPlayer.isActive)

                if showLaunch {
                    LaunchView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onOpenURL { url in
                router.handle(url)
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                // Spotlight tap — the unique ID is the SavedStory's
                // numeric id (as a string).
                guard let idString = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                      let id = Int(idString)
                else { return }
                router.handle(URL(string: "spool://story/\(id)")!)
            }
            .task {
                #if DEBUG
                // Screenshot harness — `xcrun simctl launch` can pass
                // `-SpoolStartFeed top` / `-SpoolOpenStoryID 12345` /
                // `-SpoolShowSheet settings|login|submit|nowplaying`
                // to bypass the iOS "Open in Spool?" safety prompt that
                // blocks programmatic `simctl openurl` deep-linking
                // and to reach modal sheets without UI taps. All paths
                // reuse the live router so behavior matches production.
                if let feed = UserDefaults.standard.string(forKey: "SpoolStartFeed"),
                   let url = URL(string: "spool://feed/\(feed)") {
                    router.handle(url)
                }
                if let storyArg = UserDefaults.standard.string(forKey: "SpoolOpenStoryID"),
                   let id = Int(storyArg),
                   let url = URL(string: "spool://story/\(id)") {
                    router.handle(url)
                }
                if let sheet = UserDefaults.standard.string(forKey: "SpoolShowSheet") {
                    router.pendingSheet = sheet.lowercased()
                }
                #endif
                // ~1.3s total — enough time for the three bars to
                // stagger in, the wordmark to settle, AND give the main
                // view a few extra frames to finish its first layout
                // pass underneath. Dismissing too early lets the
                // crossfade race the list's first-render work, which
                // shows up as a dropped frame near the very end of the
                // splash animation.
                try? await Task.sleep(for: .milliseconds(1_300))
                withAnimation(.easeInOut(duration: Theme.AnimationDuration.splash)) {
                    showLaunch = false
                }
            }
        }
        .modelContainer(for: [
            SavedStory.self,
            ReadStory.self,
            SpooledStory.self,
            ScoreSnapshot.self,
            FollowedUser.self,
            SeenMention.self,
        ])
        // Register the Mentions background refresh handler. iOS calls
        // this when it decides our app gets a runtime budget — could
        // be 30 minutes from now or hours, depending on user habits
        // and battery state. We just run the same check-and-notify
        // pipeline the in-app "Test BG Refresh" button does, then
        // reschedule.
        .backgroundTask(.appRefresh(MentionsNotifier.taskIdentifier)) {
            await MentionsNotifier.runMentionsCheckAndNotify(
                username: await HNAuthService.shared.currentUser
            )
            MentionsNotifier.scheduleNextRefresh()
        }
        .onChange(of: scenePhase) { _, phase in
            // The earliest window iOS will run our refresh in starts
            // from the next time we submit. Submit on every background
            // transition so the freshest interval is always pending.
            if phase == .background {
                MentionsNotifier.scheduleNextRefresh()
            }
        }
    }
}
