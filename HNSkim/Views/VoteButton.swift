import SwiftUI

@MainActor
final class VoteState: ObservableObject {
    @Published var direction: Direction = .none
    @Published var inFlight = false
    @Published var error: String?

    enum Direction { case none, up }
}

struct VoteButton: View {
    let itemID: Int
    let score: Int
    @EnvironmentObject private var auth: AuthViewModel
    @StateObject private var state = VoteState()
    @Binding var showLogin: Bool

    private var displayScore: Int {
        // Reflect the upvote optimistically so the count bumps the moment
        // the user taps.
        state.direction == .up ? score + 1 : score
    }

    var body: some View {
        Button {
            guard auth.isLoggedIn else { showLogin = true; return }
            Task { await castVote() }
        } label: {
            Label {
                Text("\(displayScore)").monospacedDigit()
            } icon: {
                if state.inFlight {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: state.direction == .up ? "arrow.up.circle.fill" : "arrow.up")
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(Theme.accent)
        .disabled(state.inFlight)
        .sensoryFeedback(.success, trigger: state.direction)
        .sensoryFeedback(.error, trigger: state.error)
        .alert("Couldn't Vote", isPresented: voteErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.error ?? "Try again.")
        }
    }

    private var voteErrorBinding: Binding<Bool> {
        Binding {
            state.error != nil
        } set: { isPresented in
            if !isPresented {
                state.error = nil
            }
        }
    }

    private func castVote() async {
        let previous = state.direction
        let newDirection: VoteState.Direction = previous == .up ? .none : .up
        // Optimistic update — UI flips and the score bumps the moment the
        // user taps. We roll back if the server call fails.
        state.direction = newDirection
        state.inFlight = true
        state.error = nil
        defer { state.inFlight = false }
        do {
            let dir: HNAuthService.VoteDirection = previous == .up ? .un : .up
            try await HNAuthService.shared.vote(itemID: itemID, direction: dir)
        } catch {
            state.direction = previous
            state.error = error.localizedDescription
        }
    }
}
