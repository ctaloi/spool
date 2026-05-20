import Foundation

@MainActor
final class UserProfileViewModel: ObservableObject {
    @Published private(set) var user: HNUser?
    @Published private(set) var submissions: [HNUserSubmission] = []
    @Published private(set) var comments: [HNUserComment] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private(set) var username: String = ""

    func load(username: String) async {
        guard username != self.username || (user == nil && errorMessage == nil) else { return }
        self.username = username
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let userTask = HNUserService.shared.user(id: username)
            async let subsTask = HNUserService.shared.submissions(by: username)
            async let cmtsTask = HNUserService.shared.comments(by: username)
            let (user, subs, cmts) = try await (userTask, subsTask, cmtsTask)
            self.user = user
            self.submissions = subs
            self.comments = cmts
        } catch is CancellationError {
            // navigation cancellation — silent
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
