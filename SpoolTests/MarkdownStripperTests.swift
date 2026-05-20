import Testing
import Foundation
@testable import Spool

/// MarkdownStripper.strip converts the AI summary's Markdown into a
/// flat, TTS-friendly paragraph for the Spool playlist: bullets
/// become sentences, headings lose their `#`s, inline emphasis
/// markers disappear, numbered lists shed their leading digits.
/// These tests cover every transform the TTS path depends on.
struct StripMarkdownTests {

    @Test func bulletPrefixRemoved() {
        let out = MarkdownStripper.strip("- First point.\n- Second point.")
        #expect(out == "First point. Second point.")
    }

    @Test func headingHashesRemoved() {
        let out = MarkdownStripper.strip("## A heading\nSome body.")
        #expect(out.contains("A heading"))
        #expect(!out.contains("#"))
    }

    @Test func boldMarkersRemoved() {
        let out = MarkdownStripper.strip("This is **bold** text.")
        #expect(out == "This is bold text.")
    }

    @Test func italicMarkersRemoved() {
        let out = MarkdownStripper.strip("This is *italic* and _also italic_.")
        #expect(!out.contains("*"))
        #expect(!out.contains("_"))
    }

    @Test func codeBackticksRemoved() {
        let out = MarkdownStripper.strip("Use `git commit` to save.")
        #expect(!out.contains("`"))
        #expect(out.contains("git commit"))
    }

    @Test func numberedListPrefixStripped() {
        let out = MarkdownStripper.strip("1. First\n2. Second\n3. Third")
        #expect(out == "First. Second. Third.")
    }

    @Test func emptyLinesAreDropped() {
        let out = MarkdownStripper.strip("Para one.\n\n\nPara two.")
        #expect(out == "Para one. Para two.")
    }

    @Test func eachLineEndsWithSentenceTerminator() {
        // Lines without trailing punctuation get a period appended
        // so the synth pauses naturally between them.
        let out = MarkdownStripper.strip("A heading\nSome body")
        // Both lines should end with `.` (joined with space).
        #expect(out.contains("A heading."))
        #expect(out.hasSuffix("."))
    }

    @Test func existingTerminatorsArePreserved() {
        let out = MarkdownStripper.strip("Question?\nExclaim!")
        #expect(out == "Question? Exclaim!")
    }

    @Test func unicodeBulletsAlsoStripped() {
        // The summarizer occasionally uses fancier bullet glyphs
        // when emulating designed lists.
        let out = MarkdownStripper.strip("• First\n‣ Second\n· Third")
        #expect(out.contains("First"))
        #expect(out.contains("Second"))
        #expect(out.contains("Third"))
        #expect(!out.contains("•"))
        #expect(!out.contains("‣"))
        #expect(!out.contains("·"))
    }

    @Test func emptyInputReturnsEmpty() {
        #expect(MarkdownStripper.strip("") == "")
    }

    @Test func mixedDocumentRoundtrips() {
        // Composite of everything: heading + bullets + bold + italic
        // + numbered list. Final output is one TTS-ready paragraph.
        let md = """
        ## Today

        - **First** point.
        - *Second* point with `inline code`.

        1. Numbered item.
        2. Another one.
        """
        let out = MarkdownStripper.strip(md)
        #expect(out.contains("Today"))
        #expect(out.contains("First point."))
        #expect(out.contains("Second point with inline code."))
        #expect(out.contains("Numbered item."))
        #expect(out.contains("Another one."))
        #expect(!out.contains("#"))
        #expect(!out.contains("*"))
        #expect(!out.contains("_"))
        #expect(!out.contains("`"))
        #expect(!out.contains("- "))
    }
}
