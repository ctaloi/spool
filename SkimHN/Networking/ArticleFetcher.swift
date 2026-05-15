import Foundation

/// Preview metadata scraped from an article's `<head>`. Used by the
/// thumbnail in the story row; cheap and never blocks navigation.
struct ArticlePreview: Sendable {
    let imageURL: URL?
}

actor ArticleFetcher {
    static let shared = ArticleFetcher()

    /// NSCache evicts under memory pressure and caps itself; the previous
    /// `[URL: String]` dictionary grew for the process lifetime.
    private let cache: NSCache<NSURL, NSString> = {
        let c = NSCache<NSURL, NSString>()
        c.countLimit = 100
        c.totalCostLimit = 4 * 1024 * 1024 // ~4 MB of stripped article text
        return c
    }()

    /// Parallel cache of just the OG/Twitter image URL for a given
    /// article URL. NSString-backed so we can `.absoluteString` round-trip
    /// without keeping a separate Sendable wrapper.
    private let previewCache: NSCache<NSURL, NSString> = {
        let c = NSCache<NSURL, NSString>()
        c.countLimit = 500
        return c
    }()

    /// Sentinel for "we looked, no image was found". Lets us avoid
    /// re-fetching pages that we already know don't expose an OG tag.
    /// Compared by content (empty string) rather than identity so it
    /// works correctly regardless of NSString interning.
    private let previewMissSentinel: NSString = ""

    /// In-flight preview fetches keyed by article URL — coalesces so a
    /// fast-scrolling feed doesn't hit the same article five times.
    private var inFlightPreviews: [URL: Task<ArticlePreview, Error>] = [:]

    func fetchText(from url: URL, maxCharacters: Int = 12_000) async throws -> String {
        if let cached = cache.object(forKey: url as NSURL) {
            return String((cached as String).prefix(maxCharacters))
        }

        let (html, _) = try await fetchHTML(from: url)
        let text = Self.stripHTML(html)
        cache.setObject(text as NSString, forKey: url as NSURL, cost: text.utf8.count)
        return String(text.prefix(maxCharacters))
    }

    /// Returns the article's OG/Twitter image URL if any. Result is
    /// cached including the "no image" case, so repeated lookups for the
    /// same article are free.
    func fetchPreview(from url: URL) async throws -> ArticlePreview {
        if let cached = previewCache.object(forKey: url as NSURL) {
            // Empty string is the "we looked, none found" sentinel.
            if (cached as String).isEmpty {
                return ArticlePreview(imageURL: nil)
            }
            return ArticlePreview(imageURL: URL(string: cached as String))
        }
        if let existing = inFlightPreviews[url] {
            return try await existing.result.get()
        }
        let task = Task<ArticlePreview, Error> {
            defer { Task { await self.clearPreviewInFlight(url) } }
            let (html, _) = try await fetchHTML(from: url)
            let imageURL = Self.extractPreviewImage(from: html, base: url)
            if let imageURL {
                self.previewCache.setObject(
                    imageURL.absoluteString as NSString,
                    forKey: url as NSURL
                )
            } else {
                self.previewCache.setObject(self.previewMissSentinel, forKey: url as NSURL)
            }
            return ArticlePreview(imageURL: imageURL)
        }
        inFlightPreviews[url] = task
        return try await task.value
    }

    private func clearPreviewInFlight(_ url: URL) {
        inFlightPreviews[url] = nil
    }

    private func fetchHTML(from url: URL) async throws -> (String, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605 (KHTML, like Gecko) Version/17 Safari/605",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        return (html, response)
    }

    /// Scrape `og:image`, falling back to `twitter:image`. Handles both
    /// attribute orders (`property="og:image" content="..."` and the
    /// reverse) since publishers vary. Resolves relative URLs against the
    /// article URL.
    static func extractPreviewImage(from html: String, base: URL) -> URL? {
        let head = String(html.prefix(60_000)) // OG tags live in <head>
        let patterns = [
            // property/name first, content second
            #"<meta\s+(?:property|name)=["'](?:og:image(?::secure_url)?|twitter:image)["'][^>]*?content=["']([^"']+)["']"#,
            // content first, property/name second
            #"<meta\s+content=["']([^"']+)["'][^>]*?(?:property|name)=["'](?:og:image(?::secure_url)?|twitter:image)["']"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) else { continue }
            let range = NSRange(head.startIndex..., in: head)
            if let match = regex.firstMatch(in: head, range: range),
               match.numberOfRanges > 1,
               let captureRange = Range(match.range(at: 1), in: head) {
                let raw = String(head[captureRange])
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let url = URL(string: raw, relativeTo: base)?.absoluteURL {
                    return url
                }
            }
        }
        return nil
    }

    static func stripHTML(_ html: String) -> String {
        var text = html

        // Drop noisy non-content sections first.
        let removePatterns = [
            #"<script[^>]*>[\s\S]*?</script>"#,
            #"<style[^>]*>[\s\S]*?</style>"#,
            #"<noscript[^>]*>[\s\S]*?</noscript>"#,
            #"<!--[\s\S]*?-->"#,
            #"<svg[^>]*>[\s\S]*?</svg>"#
        ]
        for pattern in removePatterns {
            text = text.replacingOccurrences(
                of: pattern, with: " ", options: .regularExpression
            )
        }

        // Replace block tags with newlines so paragraphs stay separated.
        let blockTags = #"</(p|div|section|article|li|h[1-6]|br|tr)>"#
        text = text.replacingOccurrences(of: blockTags, with: "\n", options: .regularExpression)

        // Strip remaining tags.
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)

        // Decode common entities.
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"),
            ("&hellip;", "…"), ("&mdash;", "—"), ("&ndash;", "–"),
            ("&rsquo;", "'"), ("&lsquo;", "'"), ("&rdquo;", "\""), ("&ldquo;", "\"")
        ]
        for (k, v) in entities {
            text = text.replacingOccurrences(of: k, with: v)
        }

        // Numeric entities like &#1234;
        text = text.replacingOccurrences(
            of: #"&#(\d+);"#,
            with: "",
            options: .regularExpression
        )

        // Collapse whitespace runs but preserve paragraph breaks.
        text = text.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
