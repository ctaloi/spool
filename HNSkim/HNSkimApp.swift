import SwiftUI
import SwiftData

@main
struct HNSkimApp: App {
    @StateObject private var auth = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            StoryListView()
                .environmentObject(auth)
                .tint(Theme.accent)
        }
        .modelContainer(for: [SavedStory.self, ReadStory.self])
    }
}
