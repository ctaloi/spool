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

    /// Votes on a story or comment. Requires login.
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
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw AuthError.network("Vote failed")
        }
    }

    /// HN puts a per-action `auth` token on each link on the item page. We
    /// fetch the page, find the link for `id=<itemID>&how=<action>`, and
    /// extract its `auth` parameter.
    private func fetchAuthToken(for itemID: Int, action: String) async throws -> String {
        let url = baseURL.appendingPathComponent("item")
            .appending(queryItems: [URLQueryItem(name: "id", value: "\(itemID)")])
        var req = URLRequest(url: url)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: req)
        guard var body = String(data: data, encoding: .utf8) else {
            throw AuthError.parsing("Couldn't read item page")
        }
        // HN's HTML escapes the `&` in vote links as `&amp;`, so the raw
        // body looks like `vote?id=X&amp;how=up&amp;auth=ABC`. Normalize
        // back to bare ampersands before matching.
        body = body.replacingOccurrences(of: "&amp;", with: "&")
        let pattern = #"vote\?id=\#(itemID)&how=\#(action)&auth=([0-9a-f]+)"#
        if let range = body.range(of: pattern, options: .regularExpression) {
            let match = String(body[range])
            if let authRange = match.range(of: "auth=") {
                return String(match[authRange.upperBound...])
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
        if let body = String(data: data, encoding: .utf8),
           let match = body.range(of: #"item\?id=(\d+)"#, options: .regularExpression) {
            let s = String(body[match])
            return Int(s.dropFirst("item?id=".count))
        }
        return nil
    }

    // MARK: - Reply

    /// Posts a reply to an existing item. Requires login. Scrapes the
    /// `hmac` token from `/reply?id=…` and POSTs to `/comment`.
    func reply(parentID: Int, text: String) async throws {
        guard isLoggedIn else { throw AuthError.notLoggedIn }
        let hmac = try await fetchReplyHmac(parentID: parentID)

        var req = URLRequest(url: baseURL.appendingPathComponent("comment"))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = Self.formEncode([
            "parent": "\(parentID)",
            "goto": "item?id=\(parentID)",
            "hmac": hmac,
            "text": text
        ])

        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse,
              (200..<400).contains(http.statusCode) else {
            throw AuthError.network("Reply failed")
        }
    }

    private func fetchReplyHmac(parentID: Int) async throws -> String {
        let url = baseURL.appendingPathComponent("reply")
            .appending(queryItems: [
                URLQueryItem(name: "id", value: "\(parentID)"),
                URLQueryItem(name: "goto", value: "item?id=\(parentID)")
            ])
        var req = URLRequest(url: url)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: req)
        guard let body = String(data: data, encoding: .utf8) else {
            throw AuthError.parsing("Couldn't read reply page")
        }
        if let range = body.range(
            of: #"name="hmac"\s+value="([^"]+)""#,
            options: .regularExpression
        ) {
            let match = String(body[range])
            if let v = match.range(of: #"value="([^"]+)""#, options: .regularExpression) {
                let raw = String(match[v])
                return raw
                    .replacingOccurrences(of: "value=\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
            }
        }
        throw AuthError.parsing("Couldn't find reply token (try signing in again)")
    }

    private func fetchSubmitFnid() async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("submit"))
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: req)
        guard let body = String(data: data, encoding: .utf8) else {
            throw AuthError.parsing("Submit page unavailable")
        }
        if let range = body.range(
            of: #"name=\"fnid\"[^>]*value=\"([^\"]+)\""#,
            options: .regularExpression
        ) {
            let match = String(body[range])
            if let v = match.range(of: #"value=\"([^\"]+)\""#, options: .regularExpression) {
                let raw = String(match[v])
                return raw
                    .replacingOccurrences(of: "value=\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
            }
        }
        throw AuthError.parsing("Couldn't find submission token (try signing in again)")
    }

    // MARK: - Utility

    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) " +
        "AppleWebKit/605 (KHTML, like Gecko) Version/26 Mobile Safari/605"

    private static func formEncode(_ fields: [String: String]) -> Data {
        let pairs = fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
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
