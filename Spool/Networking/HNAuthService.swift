import Foundation

/// Cookie-based auth + actions against the regular news.ycombinator.com web UI.
/// HN has no public auth API — we POST to /login and scrape `auth` tokens from
/// /item pages for vote/unvote operations.
actor HNAuthService {
    static let shared = HNAuthService()

    private let baseURL = URL(string: "https://news.ycombinator.com")!
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: config)
    }

    /// Test-only init that lets fixtures inject a stubbed
    /// URLSession (typically with `URLProtocolStub`'s protocol
    /// classes wired in). Production callers should keep using
    /// the shared singleton; the default `init()` configures the
    /// cookie jar correctly for live HN auth.
    init(session: URLSession) {
        self.session = session
    }

    // MARK: - Session state

    var isLoggedIn: Bool {
        cookie(named: "user") != nil
    }

    var currentUser: String? {
        get { UserDefaults.standard.string(forKey: "hn.user") }
    }

    private func setCurrentUser(_ user: String?) {
        UserDefaults.standard.set(user, forKey: "hn.user")
    }

    private func cookie(named name: String) -> HTTPCookie? {
        HTTPCookieStorage.shared.cookies(for: baseURL)?.first { $0.name == name }
    }

    // MARK: - Login / logout

    enum AuthError: LocalizedError {
        case badCredentials
        case network(String)
        case parsing(String)
        case notLoggedIn

        var errorDescription: String? {
            switch self {
            case .badCredentials: return "Bad username or password."
            case .network(let s): return s
            case .parsing(let s): return s
            case .notLoggedIn:    return "Sign in to vote or submit."
            }
        }
    }

    func login(username: String, password: String) async throws {
        let url = baseURL.appendingPathComponent("login")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("https://news.ycombinator.com/login", forHTTPHeaderField: "Referer")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = Self.formEncode([
            "acct": username,
            "pw": password,
            "goto": "news"
        ])

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.network("No response from server")
        }
        if !(200..<400).contains(http.statusCode) {
            throw AuthError.network("HTTP \(http.statusCode)")
        }

        // On bad creds HN returns the login page again containing "Bad login.".
        if let body = String(data: data, encoding: .utf8),
           body.contains("Bad login") {
            throw AuthError.badCredentials
        }

        guard cookie(named: "user") != nil else {
            throw AuthError.badCredentials
        }
        setCurrentUser(username)
    }

    func logout() async {
        if let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) {
            cookies.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        }
        setCurrentUser(nil)
    }

    // MARK: - Vote

    enum VoteDirection: String {
        case up, un  // HN uses "un" to unvote
    }

    /// Votes on a story or comment. Requires login. Like `reply`,
    /// HN never returns a 4xx for a rejected vote — it 200's with
    /// an HTML page somewhere unexpected. We detect that by
    /// checking the final URL path after URLSession's auto-redirect.
    func vote(itemID: Int, direction: VoteDirection) async throws {
        guard isLoggedIn else { throw AuthError.notLoggedIn }
        let auth = try await fetchAuthToken(for: itemID, action: direction.rawValue)

        var components = URLComponents(url: baseURL.appendingPathComponent("vote"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "id", value: "\(itemID)"),
            URLQueryItem(name: "how", value: direction.rawValue),
            URLQueryItem(name: "auth", value: auth),
            URLQueryItem(name: "goto", value: "item?id=\(itemID)")
        ]
        var req = URLRequest(url: components.url!)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("https://news.ycombinator.com/item?id=\(itemID)", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse,
              (200..<400).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AuthError.network("Vote failed (HTTP \(code))")
        }
        if let finalPath = http.url?.path, finalPath != "/item" {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AuthError.network(Self.diagnose(rejectionBody: body)
                                    ?? "HN rejected the vote (final URL: \(finalPath)).")
        }
    }

    /// HN puts a per-action `auth` token on each vote link rendered
    /// into the item page. We fetch the page, find every `vote?…`
    /// link, parse it as URL components, and pick the one whose
    /// `id` + `how` parameters match. URL-component parsing means
    /// we don't have to assume HN's preferred parameter ordering —
    /// HN has shipped both `id&how&auth&goto` and
    /// `id&how&goto&auth` over time.
    private func fetchAuthToken(for itemID: Int, action: String) async throws -> String {
        let url = baseURL.appendingPathComponent("item")
            .appending(queryItems: [URLQueryItem(name: "id", value: "\(itemID)")])
        var req = URLRequest(url: url)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: req)
        if let finalPath = (response as? HTTPURLResponse)?.url?.path,
           finalPath == "/login" {
            throw AuthError.notLoggedIn
        }
        guard var body = String(data: data, encoding: .utf8) else {
            throw AuthError.parsing("Couldn't read item page")
        }
        // HN HTML-escapes `&` in href attributes — decode once.
        body = body.replacingOccurrences(of: "&amp;", with: "&")

        guard let regex = try? NSRegularExpression(pattern: #"vote\?[^"'<>\s]+"#) else {
            throw AuthError.parsing("Vote-link regex failed to compile")
        }
        let nsRange = NSRange(body.startIndex..., in: body)
        for match in regex.matches(in: body, range: nsRange) {
            guard let matchRange = Range(match.range, in: body) else { continue }
            let link = String(body[matchRange])
            guard let comps = URLComponents(string: link),
                  let items = comps.queryItems else { continue }
            var params: [String: String] = [:]
            for item in items { params[item.name] = item.value }
            if params["id"] == "\(itemID)",
               params["how"] == action,
               let auth = params["auth"], !auth.isEmpty {
                return auth
            }
        }
        throw AuthError.parsing("Couldn't find auth token (already voted, or item locked?)")
    }

    // MARK: - Submit

    /// Submits a story. Either `url` or `text` should be provided.
    /// Returns the new item ID if HN's response makes it parseable.
    @discardableResult
    func submit(title: String, url: String? = nil, text: String? = nil) async throws -> Int? {
        guard isLoggedIn else { throw AuthError.notLoggedIn }
        let fnid = try await fetchSubmitFnid()

        var req = URLRequest(url: baseURL.appendingPathComponent("r"))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("https://news.ycombinator.com/submit", forHTTPHeaderField: "Referer")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        var fields: [String: String] = [
            "fnid": fnid,
            "fnop": "submit-page",
            "title": title
        ]
        if let url, !url.isEmpty { fields["url"] = url }
        if let text, !text.isEmpty { fields["text"] = text }
        req.httpBody = Self.formEncode(fields)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.network("No response")
        }
        if !(200..<400).contains(http.statusCode) {
            throw AuthError.network("HTTP \(http.statusCode)")
        }

        let body = String(data: data, encoding: .utf8) ?? ""

        // Successful submission redirects to /newest (the new-stories
        // feed, where the just-posted item appears at the top) or
        // directly to /item?id=X. A non-redirect landing means HN
        // re-rendered /r or /submit with an error page.
        if let finalPath = http.url?.path,
           finalPath != "/newest", !finalPath.hasPrefix("/item") {
            throw AuthError.network(Self.diagnose(rejectionBody: body)
                                    ?? "HN rejected the submission (final URL: \(finalPath)).")
        }

        if let match = body.range(of: #"item\?id=(\d+)"#, options: .regularExpression) {
            let s = String(body[match])
            return Int(s.dropFirst("item?id=".count))
        }
        return nil
    }

    // MARK: - Reply

    /// Posts a reply to an existing item. Requires login. Scrapes the
    /// `hmac` token from `/reply?id=…` and POSTs to `/comment`.
    ///
    /// HN never returns a 4xx for a rejected post — it always returns
    /// 200 OK with an HTML error page in the body. We detect those
    /// failure modes by inspecting the final URL (success redirects
    /// to `/item`, rejection stays on `/r` or hits `/x`) and by
    /// scanning the body for known error markers.
    func reply(parentID: Int, text: String) async throws {
        guard isLoggedIn else { throw AuthError.notLoggedIn }
        let hmac = try await fetchReplyHmac(parentID: parentID)

        var req = URLRequest(url: baseURL.appendingPathComponent("comment"))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("https://news.ycombinator.com/reply?id=\(parentID)", forHTTPHeaderField: "Referer")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = Self.formEncode([
            "parent": "\(parentID)",
            "goto": "item?id=\(parentID)",
            "hmac": hmac,
            "text": text
        ])

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse,
              (200..<400).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AuthError.network("Reply failed (HTTP \(code))")
        }

        // Success path: HN issues a 302 to /item?id=X — URLSession
        // follows transparently, so the final response URL ends in
        // /item. Anything else means HN rejected the post.
        if let finalPath = http.url?.path,
           finalPath != "/item" {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AuthError.network(Self.diagnose(rejectionBody: body)
                                    ?? "HN rejected the reply (final URL: \(finalPath)).")
        }
    }

    /// HN error pages — fetch returns 200 OK, body has telltale text.
    /// Returns a user-readable explanation, or nil if no marker hit.
    static func diagnose(rejectionBody body: String) -> String? {
        let markers: [(String, String)] = [
            ("You're posting too fast",      "You're posting too fast. Wait a minute and try again."),
            ("posting too fast",             "You're posting too fast. Wait a minute and try again."),
            ("please slow down",             "HN is asking you to slow down. Try again shortly."),
            ("Validation required",          "HN wants you to verify (CAPTCHA). Open in Safari to clear it."),
            ("That's not a valid",           "HN said the form data wasn't valid. Try signing out and back in."),
            ("Unknown or expired link",      "The reply link expired. Try again from a fresh story view."),
            ("login.*method=\"post\"",       "Your session expired. Sign out and back in.")
        ]
        for (needle, message) in markers {
            if body.range(of: needle, options: [.caseInsensitive, .regularExpression]) != nil {
                return message
            }
        }
        return nil
    }

    private func fetchReplyHmac(parentID: Int) async throws -> String {
        let url = baseURL.appendingPathComponent("reply")
            .appending(queryItems: [
                URLQueryItem(name: "id", value: "\(parentID)"),
                URLQueryItem(name: "goto", value: "item?id=\(parentID)")
            ])
        var req = URLRequest(url: url)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: req)

        // Expired session: HN serves the login form at /reply when
        // the cookie is gone. Surface a useful error instead of the
        // generic "couldn't find token" path.
        if let finalPath = (response as? HTTPURLResponse)?.url?.path,
           finalPath == "/login" {
            throw AuthError.notLoggedIn
        }
        guard let body = String(data: data, encoding: .utf8) else {
            throw AuthError.parsing("Couldn't read reply page")
        }
        if body.range(of: #"<form[^>]*action="login""#, options: .regularExpression) != nil {
            throw AuthError.notLoggedIn
        }

        return try Self.extractFormValue(named: "hmac", from: body)
            ?? { throw AuthError.parsing("Couldn't find reply token. Try signing out and back in.") }()
    }

    /// Extract an `<input>` value attribute by `name`, tolerant of
    /// any other attributes appearing in either order around it.
    /// Returns nil if no matching input is found.
    static func extractFormValue(named name: String, from body: String) -> String? {
        // Try name-before-value and value-before-name. HN's HTML is
        // hand-rolled and has been known to drift between releases.
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            #"name="\#(escaped)"[^>]*?value="([^"]+)""#,
            #"value="([^"]+)"[^>]*?name="\#(escaped)""#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(body.startIndex..., in: body)
            if let match = regex.firstMatch(in: body, range: range),
               match.numberOfRanges >= 2,
               let captureRange = Range(match.range(at: 1), in: body) {
                return String(body[captureRange])
            }
        }
        return nil
    }

    private func fetchSubmitFnid() async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("submit"))
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: req)
        if let finalPath = (response as? HTTPURLResponse)?.url?.path,
           finalPath == "/login" {
            throw AuthError.notLoggedIn
        }
        guard let body = String(data: data, encoding: .utf8) else {
            throw AuthError.parsing("Submit page unavailable")
        }
        if body.range(of: #"<form[^>]*action="login""#, options: .regularExpression) != nil {
            throw AuthError.notLoggedIn
        }
        guard let value = Self.extractFormValue(named: "fnid", from: body) else {
            throw AuthError.parsing("Couldn't find submission token. Try signing out and back in.")
        }
        return value
    }

    // MARK: - Utility

    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) " +
        "AppleWebKit/605 (KHTML, like Gecko) Version/26 Mobile Safari/605"

    /// Character set safe to leave un-percent-encoded inside an
    /// `application/x-www-form-urlencoded` body. Note we deliberately
    /// exclude `& = + ? #` — Apple's `.urlQueryAllowed` keeps those
    /// untouched (correct for URL query strings, wrong for form
    /// bodies, since they act as field delimiters there). The
    /// previous version of this method silently truncated comments
    /// containing any of those characters.
    static let formBodyAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+?#")
        return set
    }()

    static func formEncode(_ fields: [String: String]) -> Data {
        let pairs = fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: formBodyAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: formBodyAllowed) ?? value
            return "\(k)=\(v)"
        }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }
}

private extension URL {
    func appending(queryItems: [URLQueryItem]) -> URL {
        var c = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        c.queryItems = (c.queryItems ?? []) + queryItems
        return c.url ?? self
    }
}
