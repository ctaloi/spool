import SwiftUI

enum Theme {
    static let accent      = Color("AccentColor")
    static let accentSoft  = Color("AccentColor").opacity(0.14)

    /// Manual divider for the LazyVStack-rendered comment thread (no native
    /// separators outside of `List`).
    static let rowDivider  = Color.primary.opacity(0.06)

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
