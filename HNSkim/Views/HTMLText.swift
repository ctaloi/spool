import SwiftUI

/// Renders HN's HTML comments/text. Earlier versions used
/// `NSAttributedString(data:options:[.documentType: .html]:…)`, which is
/// WebKit-backed and notorious for release-time crashes when many
/// instances are torn down at once (e.g., collapsing/expanding comment
/// threads). This version converts the HTML to Markdown and hands it to
/// `AttributedString(markdown:)` — a pure Swift parser with no WebKit
/// dependency.
struct HTMLText: View {
    let html: String

    var body: some View {
        Text(rendered)
            // Full body size + generous line spacing — comment bodies are
            // the longest-read text in the app, so readability wins over
            // information density.
            .font(Theme.Typography.body)
            .lineSpacing(6)
            .textSelection(.enabled)
            .tint(Theme.accent)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var rendered: AttributedString {
        let markdown = Self.markdown(from: html)
        if let attr = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attr
        }
        return AttributedString(markdown)
    }

    // MARK: - HTML → Markdown

    private static func markdown(from html: String) -> String {
        var text = html

        // <a href="URL">TEXT</a>  →  [TEXT](URL)
        text = text.replacingOccurrences(
            of: #"<a[^>]*href="([^"]*)"[^>]*>([\s\S]*?)</a>"#,
            with: "[$2]($1)",
            options: .regularExpression
        )

        // Inline emphasis tags.
        for (tag, marker) in [("b", "**"), ("strong", "**"), ("i", "*"), ("em", "*")] {
            text = text.replacingOccurrences(
                of: "<\(tag)[^>]*>",
                with: marker,
                options: .regularExpression
            )
            text = text.replacingOccurrences(
                of: "</\(tag)>",
                with: marker,
                options: .regularExpression
            )
        }

        // Inline code.
        text = text.replacingOccurrences(of: "<code[^>]*>", with: "`", options: .regularExpression)
        text = text.replacingOccurrences(of: "</code>", with: "`", options: .regularExpression)

        // Paragraph and break tags → blank line / newline.
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<p[^>]*>", with: "", options: .regularExpression)

        // Strip anything else.
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)

        // Decode common entities.
        let entities: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&#x27;", "'"),
            ("&hellip;", "…"),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&rsquo;", "'"),
            ("&lsquo;", "'"),
            ("&rdquo;", "\""),
            ("&ldquo;", "\"")
        ]
        for (k, v) in entities {
            text = text.replacingOccurrences(of: k, with: v)
        }

        // Collapse runs of blank lines.
        text = text.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
