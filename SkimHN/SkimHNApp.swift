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
                // ~1.2s total — enough time for the three bars to
                // stagger in and the wordmark to settle. The main view
                // is already mounting + fetching beneath, so this is
                // pure brand presence, not added wait.
                try? await Task.sleep(for: .milliseconds(1_200))
                withAnimation(.easeInOut(duration: 0.45)) {
                    showLaunch = false
                }
            }
        }
        .modelContainer(for: [
            SavedStory.self,
            ReadStory.self,
            ReadLaterStory.self,
            ScoreSnapshot.self,
        ])
    }
}
