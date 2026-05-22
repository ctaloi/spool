import SwiftUI
import SwiftData
import CoreSpotlight

@main
struct SpoolApp: App {
    @StateObject private var auth = AuthViewModel()
    @StateObject private var router = AppRouter()
    /// Cross-screen Spool playlist controller. Held at the
    /// scene root so the mini player overlay and the playlist
    /// screen share the same controller instance.
    @StateObject private var spoolPlayer = SpoolPlayer()
    /// Observed so we can reschedule the Mentions background refresh
    /// every time the app moves to background. iOS only honors the
    /// most recently submitted request per identifier.
    @Environment(\.scenePhase) private var scenePhase
    /// One-shot guard for the Apple Intelligence first-launch gate.
    /// Set true after the user acknowledges the gate; never re-shown
    /// in the same session.
    @AppStorage(SettingsKeys.intelligenceGateSeen) private var intelligenceGateSeen: Bool = false
    /// Whether the gate is currently presented. Computed once when
    /// scenePhase first hits .active so iOS pre-warm doesn't fire it
    /// invisibly.
    @State private var showIntelligenceGate: Bool = false
    /// Snapshot of the availability the gate is showing — capture
    /// once so the message doesn't flicker if availability briefly
    /// changes (e.g., modelNotReady → available mid-screen).
    @State private var gateAvailability: SummaryAvailability = .available

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
        // BGTask handler registration happens via the SwiftUI
        // `.backgroundTask(.appRefresh(...))` modifier on the Scene
        // below — that's the iOS 16+ equivalent of calling
        // BGTaskScheduler.shared.register manually.
    }

    var body: some Scene {
        WindowGroup {
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
                // First-launch onboarding gate when Apple Intelligence
                // isn't available — spells out the situation up front
                // so users with the wrong hardware or the wrong toggle
                // state don't find broken-looking buttons later.
                .fullScreenCover(isPresented: $showIntelligenceGate) {
                    AppleIntelligenceGateView(
                        availability: gateAvailability,
                        isPresented: $showIntelligenceGate
                    )
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
            // Apple Intelligence gate evaluation. Gated on scenePhase
            // active so iOS pre-warm doesn't sneak the cover up
            // invisibly. Only ever shows once — `intelligenceGateSeen`
            // sticks even if AI becomes available later, since the
            // in-app states are clear enough on their own at that
            // point.
            if phase == .active, !intelligenceGateSeen, !showIntelligenceGate {
                let current = SummaryService.shared.availability
                if current != .available {
                    gateAvailability = current
                    showIntelligenceGate = true
                }
            }
        }
    }
}
