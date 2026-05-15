import SwiftUI
import SwiftData
import TipKit
import CoreSpotlight

@main
struct SkimHNApp: App {
    @StateObject private var auth = AuthViewModel()
    @StateObject private var router = AppRouter()
    /// `true` for the first ~1.2s of process lifetime, then false for
    /// the rest of the session. Drives the branded splash overlay.
    @State private var showLaunch: Bool = true
    /// Observed so we can reschedule the Mentions background refresh
    /// every time the app moves to background. iOS only honors the
    /// most recently submitted request per identifier.
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                StoryListView()
                    .environmentObject(auth)
                    .environmentObject(router)
                    .tint(Theme.accent)

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
                router.handle(URL(string: "skimhn://story/\(id)")!)
            }
            .task {
                // Configure TipKit so seen/dismissed state persists
                // across launches. Idempotent — safe to re-call.
                try? Tips.configure([
                    .displayFrequency(.immediate),
                    .datastoreLocation(.applicationDefault),
                ])
            }
            .task {
                // ~1.3s total — enough time for the three bars to
                // stagger in, the wordmark to settle, AND give the main
                // view a few extra frames to finish its first layout
                // pass underneath. Dismissing too early lets the
                // crossfade race the list's first-render work, which
                // shows up as a dropped frame near the very end of the
                // splash animation.
                try? await Task.sleep(for: .milliseconds(1_300))
                withAnimation(.easeInOut(duration: 0.55)) {
                    showLaunch = false
                }
            }
        }
        .modelContainer(for: [
            SavedStory.self,
            ReadStory.self,
            ReadLaterStory.self,
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
