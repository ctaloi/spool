import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published private(set) var isLoggedIn: Bool = false
    @Published private(set) var username: String?
    @Published var isWorking: Bool = false
    @Published var errorMessage: String?

    init() {
        Task { await refresh() }
    }

    func refresh() async {
        self.isLoggedIn = await HNAuthService.shared.isLoggedIn
        self.username = await HNAuthService.shared.currentUser
    }

    func login(username: String, password: String) async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await HNAuthService.shared.login(username: username, password: password)
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func logout() async {
        await HNAuthService.shared.logout()
        await refresh()
    }
}
