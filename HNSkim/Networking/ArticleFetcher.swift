import Foundation

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

    func fetchText(from url: URL, maxCharacters: Int = 12_000) async throws -> String {
        if let cached = cache.object(forKey: url as NSURL) {
            return String((cached as String).prefix(maxCharacters))
        }

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

        let text = Self.stripHTML(html)
        cache.setObject(text as NSString, forKey: url as NSURL, cost: text.utf8.count)
        return String(text.prefix(maxCharacters))
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
