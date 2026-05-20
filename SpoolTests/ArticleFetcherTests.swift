import Testing
import Foundation
@testable import Spool

/// stripHTML converts a raw web page into plain text the on-device
/// summarizer can chew on. Every transform happens via regex — these
/// tests cover the ones most likely to silently regress.
struct StripHTMLTests {

    @Test func dropsScriptContent() {
        let html = "Before<script>alert('bad')</script>After"
        let out = ArticleFetcher.stripHTML(html)
        #expect(!out.contains("alert"))
        #expect(out.contains("Before"))
        #expect(out.contains("After"))
    }

    @Test func dropsStyleContent() {
        let html = "Body<style>.x { color: red }</style>more"
        let out = ArticleFetcher.stripHTML(html)
        #expect(!out.contains("color: red"))
        #expect(out.contains("Body"))
        #expect(out.contains("more"))
    }

    @Test func dropsComments() {
        let html = "Before<!-- this is hidden -->After"
        let out = ArticleFetcher.stripHTML(html)
        #expect(!out.contains("hidden"))
    }

    @Test func dropsSvgContent() {
        let html = "<svg><path d='M10 10'/></svg>Text after"
        let out = ArticleFetcher.stripHTML(html)
        #expect(out.contains("Text after"))
        #expect(!out.contains("path"))
    }

    @Test func paragraphsBecomeNewlines() {
        let html = "<p>One.</p><p>Two.</p>"
        let out = ArticleFetcher.stripHTML(html)
        // Paragraph break preserved so the summarizer sees structure.
        #expect(out.contains("One."))
        #expect(out.contains("Two."))
    }

    @Test func stripsRemainingTags() {
        let html = "<div><span class=\"x\">Hello</span> <b>world</b></div>"
        let out = ArticleFetcher.stripHTML(html)
        #expect(!out.contains("<"))
        #expect(!out.contains(">"))
        #expect(out.contains("Hello"))
        #expect(out.contains("world"))
    }

    @Test func decodesCommonEntities() {
        let html = "Tom &amp; Jerry &lt;3 &quot;tech&quot;"
        let out = ArticleFetcher.stripHTML(html)
        #expect(out.contains("&"))
        #expect(out.contains("<"))
        #expect(out.contains("\""))
    }

    @Test func decodesSmartQuotesAndDashes() {
        let html = "He said &lsquo;hello&rsquo; &mdash; politely."
        let out = ArticleFetcher.stripHTML(html)
        #expect(out.contains("'hello'"))
        #expect(out.contains("—"))
    }

    @Test func collapsesWhitespaceRuns() {
        let html = "Word     with    lots    of    space"
        let out = ArticleFetcher.stripHTML(html)
        #expect(!out.contains("  "))
    }

    @Test func trimsLeadingAndTrailingWhitespace() {
        let html = "   <p>Hello.</p>   "
        let out = ArticleFetcher.stripHTML(html)
        #expect(out.hasPrefix("Hello"))
        #expect(out.hasSuffix("."))
    }
}
