import SwiftUI

struct MarkdownText: View {
    let text: String
    var bodyFont: Font = Theme.Typography.body
    var lineSpacing: CGFloat = 5

    var body: some View {
        // Capture the parsed block list once so spacing decisions can peek
        // at the previous block without re-parsing per row.
        let parsed = blocks
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(parsed.enumerated()), id: \.offset) { index, block in
                render(block)
                    .padding(.top, topSpacing(at: index, in: parsed))
            }
        }
    }

    /// Variable spacing so the rendered summary has visual rhythm:
    /// consecutive bullets stay tight (a list), section breaks breathe.
    /// Picks from `Theme.Spacing` so every block-level gap pulls from
    /// the same 4pt-multiple scale as the rest of the app.
    private func topSpacing(at index: Int, in blocks: [Block]) -> CGFloat {
        guard index > 0 else { return 0 }
        let prev = blocks[index - 1]
        let curr = blocks[index]
        switch (prev, curr) {
        case (.bullet, .bullet),
             (.numbered, .numbered):
            return Theme.Spacing.xs       // consecutive list items
        case (.heading, _):
            return Theme.Spacing.xs + 2   // first block under a heading
        case (_, .heading):
            return Theme.Spacing.lg       // generous break before a new section
        case (.bullet, .paragraph),
             (.numbered, .paragraph):
            return Theme.Spacing.md + 2   // list → new paragraph reads as a new section
        default:
            return Theme.Spacing.sm + 2   // paragraph → paragraph and the rest
        }
    }

    /// Font for a heading at the given level. Top-level headings (1-2)
    /// use the configured headingFont; promoted section labels (3+) render
    /// as a tight, uppercased eyebrow so they read as section dividers
    /// rather than competing with body text.
    private func font(forHeadingLevel level: Int) -> Font {
        switch level {
        case 1: return .system(.title2, design: .default, weight: .bold)
        case 2: return .system(.title3, design: .default, weight: .bold)
        default: return .system(.caption, design: .default, weight: .heavy)
        }
    }

    @ViewBuilder
    private func render(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let content):
            inline(content)
                .font(font(forHeadingLevel: level))
                .foregroundStyle(level >= 3 ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
                .textCase(level >= 3 ? .uppercase : nil)
                .tracking(level >= 3 ? 0.6 : 0)
        case .paragraph(let content):
            inline(content)
                .font(bodyFont)
                .lineSpacing(lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .bullet(let content):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(bodyFont.weight(.bold))
                    .foregroundStyle(Theme.accent)
                inline(content)
                    .font(bodyFont)
                    .lineSpacing(lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .numbered(let index, let content):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(index).")
                    .font(bodyFont.weight(.bold))
                    .foregroundStyle(Theme.accent)
                inline(content)
                    .font(bodyFont)
                    .lineSpacing(lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func inline(_ raw: String) -> Text {
        guard var attr = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else { return Text(raw) }

        // SwiftUI renders **bold** at the default heavy bold weight, which
        // reads as shouty in summary cards. Downgrade strongly-emphasized
        // ranges to semibold for a softer look.
        let boldRanges: [Range<AttributedString.Index>] = attr.runs.compactMap { run in
            (run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true) ? run.range : nil
        }
        for range in boldRanges {
            attr[range].font = bodyFont.weight(.semibold)
        }

        return Text(attr)
    }

    // MARK: - Block parsing

    private enum Block {
        case heading(level: Int, content: String)
        case paragraph(String)
        case bullet(String)
        case numbered(index: Int, content: String)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            if !paragraphBuffer.isEmpty {
                let joined = paragraphBuffer.joined(separator: " ")
                // Promote "**Label** — body" / "**Label:** body" patterns
                // into a real section heading so the rendered summary has
                // visible section breaks instead of inline bold buried in
                // a paragraph.
                if let (label, body) = Self.splitSectionLabel(joined) {
                    result.append(.heading(level: 3, content: label))
                    if !body.isEmpty {
                        result.append(.paragraph(body))
                    }
                } else {
                    result.append(.paragraph(joined))
                }
                paragraphBuffer.removeAll()
            }
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
                continue
            }

            if let (level, body) = parseHeading(line) {
                flushParagraph()
                result.append(.heading(level: level, content: body))
                continue
            }

            if let bulletContent = parseBullet(line) {
                flushParagraph()
                // Bullets stay bullets. Inline bold inside a bullet
                // is rendered as bold via AttributedString markdown
                // parsing — we deliberately do NOT promote
                // "- **Label**: body" to a heading + paragraph here.
                // Doing so used to produce a forest of orange
                // eyebrows when a "Themes" section had bullets like
                // "- **Drawers**: A macOS app for…" — each bullet
                // turned into its own loud uppercase heading. Section
                // structure now comes exclusively from paragraph-
                // level **Section**: prefixes (handled in
                // flushParagraph).
                result.append(.bullet(bulletContent))
                continue
            }

            if let (index, content) = parseNumbered(line) {
                flushParagraph()
                result.append(.numbered(index: index, content: content))
                continue
            }

            paragraphBuffer.append(line)
        }
        flushParagraph()
        return result
    }

    /// Detects "**Label** — body" / "**Label:** body" / "**Label**: body"
    /// paragraph starts and splits into (label, body). Returns nil if the
    /// paragraph doesn't look like a section header — so a paragraph that
    /// merely starts with inline bold ("**bold word** in a sentence") is
    /// left as a regular paragraph.
    private static func splitSectionLabel(_ paragraph: String) -> (label: String, body: String)? {
        let trimmed = paragraph.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("**") else { return nil }
        let afterOpening = trimmed.index(trimmed.startIndex, offsetBy: 2)
        guard let closing = trimmed.range(of: "**", range: afterOpening..<trimmed.endIndex) else {
            return nil
        }

        var label = String(trimmed[afterOpening..<closing.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        let labelHadColon = label.hasSuffix(":")
        if labelHadColon {
            label = String(label.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        guard !label.isEmpty else { return nil }

        var rest = String(trimmed[closing.upperBound...])
            .trimmingCharacters(in: .whitespaces)
        var separatorStripped = false
        while let first = rest.first,
              first == ":" || first == "—" || first == "–" || first == "-" {
            rest.removeFirst()
            separatorStripped = true
        }
        rest = rest.trimmingCharacters(in: .whitespaces)

        // Promote only if this really looks like a section header: a
        // separator between bold and body, a trailing colon inside the
        // bold, or a bold label with no body at all.
        guard separatorStripped || labelHadColon || rest.isEmpty else {
            return nil
        }

        return (label, rest)
    }

    private func parseHeading(_ line: String) -> (Int, String)? {
        var level = 0
        var i = line.startIndex
        while i < line.endIndex, line[i] == "#", level < 6 {
            level += 1
            i = line.index(after: i)
        }
        guard level > 0, i < line.endIndex, line[i] == " " else { return nil }
        let body = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
        return (level, body)
    }

    private func parseBullet(_ line: String) -> String? {
        let markers = ["- ", "* ", "+ ", "• ", "· ", "‣ "]
        for m in markers {
            if line.hasPrefix(m) {
                return String(line.dropFirst(m.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        if line == "-" || line == "*" || line == "•" { return "" }
        return nil
    }

    private func parseNumbered(_ line: String) -> (Int, String)? {
        var digits = ""
        var i = line.startIndex
        while i < line.endIndex, line[i].isNumber {
            digits.append(line[i])
            i = line.index(after: i)
        }
        guard !digits.isEmpty, i < line.endIndex else { return nil }
        let c = line[i]
        guard c == "." || c == ")" else { return nil }
        let next = line.index(after: i)
        guard next < line.endIndex, line[next] == " " else { return nil }
        let content = line[line.index(after: next)...].trimmingCharacters(in: .whitespaces)
        return (Int(digits) ?? 1, content)
    }
}
