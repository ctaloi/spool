import Foundation

/// Centralized `@AppStorage` keys so a typo in one file can't drift away
/// from another file's reader/writer of the same preference.
enum SettingsKeys {
    /// Whether to render the OG-image thumbnail in story list rows.
    /// Detail-page hero images are independent of this toggle — they
    /// always render when available.
    static let showThumbnails = "settings.showThumbnails"
}
