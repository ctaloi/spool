import SwiftUI
import SwiftData

@main
struct SkimHNApp: App {
    @StateObject private var auth = AuthViewModel()
    /// `true` for the first ~1.2s of process lifetime, then false for
    /// the rest of the session. Drives the branded splash overlay.
    @State private var showLaunch: Bool = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                StoryListView()
                    .environmentObject(auth)
                    .tint(Theme.accent)

                if showLaunch {
                    LaunchView()
                        .transition(.opacity)
                        .zIndex(1)
                }
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
    }
}
