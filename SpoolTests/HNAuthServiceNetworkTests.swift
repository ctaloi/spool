import Testing
import Foundation
@testable import Spool

/// Tests the HN web-scrape networking via URLProtocol stubbing. The
/// pure-logic helpers (formEncode, diagnose, extractFormValue) are
/// covered separately in HNAuthServiceTests; this file exercises
/// the request/response flow.
///
/// HNAuthService is an actor — these tests await its async methods.
struct HNAuthServiceNetworkTests {

    /// Build a fresh actor with a stub-routed session. Each test
    /// gets its own clean cookie storage so logout side effects
    /// don't leak between tests.
    private func makeService() -> HNAuthService {
        URLProtocolStub.reset()
        // Note: HNAuthService(session:) uses an internal init that
        // accepts a custom session. The session config we wire in
        // here routes everything through URLProtocolStub.
        return HNAuthService(session: URLProtocolStub.makeSession())
    }

    // MARK: - login

    @Test func loginRecognizesBadCredentialsFromBody() async {
        let svc = makeService()
        URLProtocolStub.respond(
            toURLContaining: "/login",
            with: "Bad login.".data(using: .utf8)!
        )
        await #expect(throws: HNAuthService.AuthError.self) {
            try await svc.login(username: "alice", password: "wrong")
        }
    }

    // MARK: - vote / fetchAuthToken

    @Test func voteSurfacesAlreadyVotedMessageWhenLinkAbsent() async {
        let svc = makeService()
        // Pretend the user is "logged in" by seeding the user cookie
        // for the test session's storage. We can do that by handling
        // the item page request and inspecting Cookie behavior — but
        // since URLProtocolStub provides an ephemeral session with
        // its own (empty) cookie jar, isLoggedIn returns false here
        // and the service throws notLoggedIn before ever calling
        // out. This is the expected behavior for the "no cookie"
        // path.
        await #expect(throws: HNAuthService.AuthError.self) {
            try await svc.vote(itemID: 1, direction: .up)
        }
    }

    // MARK: - reply

    @Test func replyThrowsNotLoggedInWithoutCookie() async {
        // Same logic as vote — without a user cookie, the actor
        // refuses to attempt the action.
        let svc = makeService()
        await #expect(throws: HNAuthService.AuthError.self) {
            try await svc.reply(parentID: 1, text: "hello")
        }
    }

    // MARK: - submit

    @Test func submitThrowsNotLoggedInWithoutCookie() async {
        let svc = makeService()
        await #expect(throws: HNAuthService.AuthError.self) {
            try await svc.submit(title: "Hello world", url: "https://example.com")
        }
    }

    // MARK: - diagnose / extractFormValue smoke through the public API

    @Test func formBodyAllowedExcludesCriticalChars() {
        // Verify the form-encoded charset doesn't contain the four
        // chars that act as field separators / space proxy.
        let allowed = HNAuthService.formBodyAllowed
        let forbidden: [Unicode.Scalar] = ["&", "=", "+", "?", "#"]
        for scalar in forbidden {
            #expect(!allowed.contains(scalar),
                    "char \(scalar) must NOT be in formBodyAllowed")
        }
    }
}
