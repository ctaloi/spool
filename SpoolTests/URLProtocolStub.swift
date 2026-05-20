import Foundation

/// Test fixture that intercepts `URLSession.data(from:)` /
/// `data(for:)` calls without hitting the network. Tests register
/// canned responses keyed by request URL substring; if a request
/// comes in that doesn't match any handler, the test fails loudly.
///
/// Usage:
/// ```
/// let session = URLProtocolStub.makeSession()
/// URLProtocolStub.respond(toURLContaining: "topstories.json", with: data)
/// let api = HNAPI(session: session)
/// ```
final class URLProtocolStub: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    /// In-flight URL-substring → handler registrations. Cleared
    /// between tests via `reset()`.
    nonisolated(unsafe) private static var handlers: [(String, Handler)] = []
    private static let lock = NSLock()

    /// Build a URLSession that routes all requests through this stub.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: config)
    }

    /// Register a handler that fires when the request URL contains
    /// the given substring. Later registrations take precedence
    /// over earlier ones for the same substring.
    static func respond(
        toURLContaining substring: String,
        with data: Data,
        statusCode: Int = 200
    ) {
        respond(toURLContaining: substring) { request in
            let url = request.url ?? URL(string: "about:blank")!
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (response, data)
        }
    }

    /// Register a custom handler that can inspect the request and
    /// build a tailored response.
    static func respond(
        toURLContaining substring: String,
        handler: @escaping Handler
    ) {
        lock.lock()
        handlers.append((substring, handler))
        lock.unlock()
    }

    /// Reset all registered handlers. Call in test setup so tests
    /// don't leak fixtures between cases.
    static func reset() {
        lock.lock()
        handlers.removeAll()
        lock.unlock()
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let snapshot = Self.handlers
        Self.lock.unlock()
        guard let url = request.url?.absoluteString else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        for (substring, handler) in snapshot.reversed() where url.contains(substring) {
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
                return
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
        }
        // No matching handler — fail loudly so the test sees it.
        client?.urlProtocol(self, didFailWithError: URLError(
            .resourceUnavailable,
            userInfo: [NSLocalizedDescriptionKey:
                       "URLProtocolStub: no handler for \(url)"]
        ))
    }

    override func stopLoading() {}
}
