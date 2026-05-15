import Foundation

/// Centralized `@AppStorage` keys so a typo in one file can't drift away
/// from another file's reader/writer of the same preference.
enum SettingsKeys {
    /// Whether to render the OG-image thumbnail in story list rows.
    /// Detail-page hero images are independent of this toggle — they
    /// always render when available.
    static let showThumbnails = "settings.showThumbnails"

    /// Timestamp of the last time the user actively opened the Top
    /// feed. Drives the catch-up digest — we only show "what you
    /// missed" once per day, the first time the user lands on Top.
    static let lastOpenedAt = "settings.lastOpenedAt"

    /// Calendar day-of-year of the user's most recent digest
    /// dismissal. Prevents the card from coming back the same day
    /// after they've cleared it.
    static let lastDigestDismissedDay = "settings.lastDigestDismissedDay"
}
