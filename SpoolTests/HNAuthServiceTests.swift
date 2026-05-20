import Testing
import Foundation
@testable import Spool

/// Pure-logic tests for HNAuthService's HTML scrape / form-encode
/// helpers. Network paths aren't covered here — those require a live
/// HN session — but the helpers below are exactly the brittle parts
/// that historically broke silently when HN tweaks its HTML.
struct HNAuthServiceTests {

    // MARK: - Form body encoding

    @Test func formEncodingEscapesAmpersand() {
        // Pre-fix: `text=hello & world` arrived to HN as field
        // `text=hello ` and a stray field ` world` — the comment
        // was silently truncated. We must encode the `&`.
        let data = HNAuthService.formEncode(["text": "hello & world"])
        let body = String(data: data, encoding: .utf8) ?? ""
        #expect(body.contains("%26"), "ampersand must be percent-encoded")
        #expect(!body.contains("hello & world"), "raw '&' must not appear")
    }

    @Test func formEncodingEscapesPlusEqualsAndHash() {
        // `+` in a form body means space (per HTML form spec), `=`
        // separates key/value, `?` is benign but conventionally
        // encoded, `#` is fragment. Apple's `.urlQueryAllowed`
        // leaves all four untouched — wrong for form bodies.
        let data = HNAuthService.formEncode([
            "text": "a+b=c?d#e"
        ])
        let body = String(data: data, encoding: .utf8) ?? ""
        #expect(body.contains("%2B"))   // +
        #expect(body.contains("%3D"))   // =
        #expect(body.contains("%3F"))   // ?
        #expect(body.contains("%23"))   // #
    }

    @Test func formEncodingPreservesAlphanumericAndCommonSafe() {
        let data = HNAuthService.formEncode(["text": "abc123-._~"])
        let body = String(data: data, encoding: .utf8) ?? ""
        #expect(body.contains("text=abc123-._~"))
    }

    @Test func formEncodingJoinsFieldsWithAmpersand() {
        let data = HNAuthService.formEncode([
            "parent": "12345",
            "hmac": "deadbeef",
        ])
        let body = String(data: data, encoding: .utf8) ?? ""
        let parts = body.split(separator: "&").map(String.init)
        #expect(parts.count == 2)
        #expect(parts.contains("parent=12345"))
        #expect(parts.contains("hmac=deadbeef"))
    }

    // MARK: - Rejection-body diagnosis

    @Test func diagnoseRecognizesPostingTooFast() {
        let message = HNAuthService.diagnose(rejectionBody: "Sorry, you're posting too fast. Please slow down.")
        #expect(message != nil)
        #expect(message?.lowercased().contains("too fast") == true
                || message?.lowercased().contains("slow down") == true)
    }

    @Test func diagnoseRecognizesValidationCaptcha() {
        let message = HNAuthService.diagnose(rejectionBody: "<p>Validation required to continue.</p>")
        #expect(message?.lowercased().contains("verify") == true
                || message?.lowercased().contains("captcha") == true)
    }

    @Test func diagnoseRecognizesExpiredLink() {
        let message = HNAuthService.diagnose(rejectionBody: "Unknown or expired link.")
        #expect(message?.lowercased().contains("expired") == true)
    }

    @Test func diagnoseRecognizesLoginRedirect() {
        // HN sometimes serves the login form back when the session
        // expired mid-action.
        let body = #"<form action="login" method="post">"#
        let message = HNAuthService.diagnose(rejectionBody: body)
        #expect(message != nil)
        #expect(message?.lowercased().contains("session") == true
                || message?.lowercased().contains("sign") == true)
    }

    @Test func diagnoseReturnsNilForUnknownBody() {
        let message = HNAuthService.diagnose(rejectionBody: "<html><body>Hello world</body></html>")
        #expect(message == nil)
    }

    @Test func diagnoseIsCaseInsensitive() {
        // The actual HN page often has "Sorry — please reload" with
        // mixed case; we shouldn't miss it because of case.
        let message = HNAuthService.diagnose(rejectionBody: "YOU'RE POSTING TOO FAST")
        #expect(message != nil)
    }

    // MARK: - <input> value extraction

    @Test func extractFormValueWithNameThenValue() {
        let html = #"<input type="hidden" name="hmac" value="abc123def">"#
        #expect(HNAuthService.extractFormValue(named: "hmac", from: html) == "abc123def")
    }

    @Test func extractFormValueWithValueThenName() {
        // Some HN forms render attributes in the reverse order.
        let html = #"<input type="hidden" value="xyz789" name="fnid">"#
        #expect(HNAuthService.extractFormValue(named: "fnid", from: html) == "xyz789")
    }

    @Test func extractFormValueIgnoresOtherInputs() {
        let html = """
            <input type="text" name="other" value="ignore-me">
            <input type="hidden" name="hmac" value="correct">
            <input type="submit" name="goto" value="news">
            """
        #expect(HNAuthService.extractFormValue(named: "hmac", from: html) == "correct")
    }

    @Test func extractFormValueReturnsNilWhenAbsent() {
        let html = #"<input type="text" name="acct" value="user">"#
        #expect(HNAuthService.extractFormValue(named: "hmac", from: html) == nil)
    }

    @Test func extractFormValueHandlesExtraAttributesBetween() {
        // HN has been known to slip `class`, `id`, `placeholder`
        // attributes between `name` and `value`. Our regex must
        // tolerate that.
        let html = #"<input name="hmac" class="hidden-field" id="hmac-input" value="deadbeef">"#
        #expect(HNAuthService.extractFormValue(named: "hmac", from: html) == "deadbeef")
    }
}
