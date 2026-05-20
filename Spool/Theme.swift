import SwiftUI

/// Centralized design tokens. The app's visual identity hangs on three
/// values: the brand accent (HN orange), the typography scale (built on
/// iOS text styles so everything respects Dynamic Type), and a small
/// set of opacities + animation durations that propagate across the
/// reader/listen/summary surfaces. Adding a constant here is cheap;
/// adding a one-off magic number scattered across multiple views is
/// where drift creeps in.
enum Theme {
    static let accent      = Color("AccentColor")
    static let accentSoft  = Color("AccentColor").opacity(Opacity.accentSoft)

    /// Manual divider for the LazyVStack-rendered comment thread (no native
    /// separators outside of `List`).
    static let rowDivider  = Color.primary.opacity(Opacity.rowDivider)

    /// Opacity tokens. Centralized so the read/written/upcoming gradient
    /// in the now-playing scroller, the read-row dimming in the feed,
    /// and the selection tint on iPad don't drift from each other.
    enum Opacity {
        /// Read-row title in the feed (matches Apple Mail's read-thread treatment).
        static let readPrimary: CGFloat = 0.55
        /// Read-row secondary metadata.
        static let readSecondary: CGFloat = 0.75
        /// Selected-row background tint (12% accent on iPad).
        static let selectionTint: CGFloat = 0.12
        /// "Already spoken" sentence in the now-playing scroller.
        static let upcomingText: CGFloat = 0.45
        /// Subtle row divider.
        static let rowDivider: CGFloat = 0.06
        /// Accent's soft surface (chips, pills, accent-tinted backgrounds).
        static let accentSoft: CGFloat = 0.14
        /// Now-playing item background highlight.
        static let nowPlayingRow: CGFloat = 0.08
    }

    /// Animation duration tokens. The splash crossfade and the
    /// sentence-scroll auto-advance share a coordinated cadence; the
    /// individual launch-bar stagger and the wordmark fade align to
    /// the same beat so the splash feels like one motion.
    enum AnimationDuration {
        /// Micro animations — symbol toggles, small state flips.
        static let micro: Double = 0.18
        /// State-change easings — button state, control feedback.
        static let fast: Double = 0.2
        /// Crossfades and value transitions — thumbnails, smaller cards.
        static let quick: Double = 0.25
        /// Mid-tier transitions — feed switches, list/card morphs.
        static let medium: Double = 0.3
        /// Standard interaction tempo — launch bars, navigation swaps.
        static let standard: Double = 0.32
        /// Cross-fade and lingering motion — wordmark fade, scroll auto-advance.
        static let slow: Double = 0.42
        /// Hero motion — splash dismiss, hero-image color settle.
        static let splash: Double = 0.55
    }

    /// 4pt-multiple spacing scale. Reuse across cards, padding,
    /// stack spacings so the layout grid stays coherent. Not every
    /// magic number must come from here — context-specific values
    /// (e.g., a tiny separator's 2pt frame) can be inline — but
    /// general-purpose padding/gap should pick from this scale.
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 22
        static let xxl: CGFloat = 32
    }

    /// Card and pill rounding. iOS conventions land near 10pt for
    /// row-level rects, 12pt for in-card surfaces (editor wells,
    /// disclosure backgrounds), 14pt for top-level cards, 20pt for
    /// prominent surfaces.
    enum CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 10
        static let card: CGFloat = 12
        static let large: CGFloat = 14
        static let xlarge: CGFloat = 20
    }

    /// HIG minimum tap target. Anywhere a control depends on a
    /// finger tap (not just keyboard / external pointer), its hit
    /// area should be at least this big. Use `.frame(minWidth:
    /// Theme.Layout.tapTargetMinimum, minHeight: …)` on icon-only
    /// buttons that would otherwise size to the glyph.
    enum Layout {
        static let tapTargetMinimum: CGFloat = 44
        /// Min height for multi-line editors (PromptEditorView,
        /// Submit text field). Sized for ~10 lines of body text at
        /// default Dynamic Type, generous enough to feel like a
        /// composition surface, not a single-line input.
        static let editorMinHeight: CGFloat = 280
    }

    /// Typography scale built on iOS text styles so every label respects
    /// Dynamic Type. Uses the system font (SF Pro) for clarity at small
    /// sizes and weight pairings tuned for a dense feed UI.
    enum Typography {
        static let largeTitle      = Font.system(.largeTitle, design: .default, weight: .bold)
        static let title           = Font.system(.title2,     design: .default, weight: .bold)
        static let sectionTitle    = Font.system(.title3,     design: .default, weight: .semibold)

        /// Top-of-row story titles and inline emphasis.
        static let headline        = Font.system(.headline,   design: .default)
        /// Default reading text: summary bodies, comment bodies.
        static let body            = Font.system(.body,       design: .default)
        static let bodyEmphasized  = Font.system(.body,       design: .default, weight: .semibold)

        /// Secondary text used next to body content (timestamps, by-lines).
        static let callout         = Font.system(.callout,    design: .default)
        static let calloutStrong   = Font.system(.callout,    design: .default, weight: .semibold)

        static let subheadline     = Font.system(.subheadline, design: .default)
        static let subheadlineStrong = Font.system(.subheadline, design: .default, weight: .semibold)

        static let footnote        = Font.system(.footnote,   design: .default)
        static let footnoteStrong  = Font.system(.footnote,   design: .default, weight: .semibold)

        static let caption         = Font.system(.caption,    design: .default)
        static let captionStrong   = Font.system(.caption,    design: .default, weight: .semibold)
        static let caption2        = Font.system(.caption2,   design: .default)
        static let caption2Strong  = Font.system(.caption2,   design: .default, weight: .semibold)

        /// Toolbar brand wordmark.
        static let brand           = Font.system(.headline,   design: .default, weight: .heavy)

        /// Tabular numerals for scores / counts so columns don't jitter.
        static let score           = Font.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit()
        static let scoreCompact    = Font.system(.footnote,   design: .rounded, weight: .semibold).monospacedDigit()
    }
}
