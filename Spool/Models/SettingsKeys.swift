import Foundation

/// Centralized `@AppStorage` keys so a typo in one file can't drift away
/// from another file's reader/writer of the same preference.
enum SettingsKeys {
    /// Whether to render the OG-image thumbnail in story list rows.
    /// Detail-page hero images are independent of this toggle — they
    /// always render when available.
    static let showThumbnails = "settings.showThumbnails"

    /// Hide stories the user has already opened from category /
    /// trending / best-of feeds. Saved + Spool are exempt — those
    /// are user-curated lists where hiding "read" items would surprise.
    static let hideReadStories = "settings.hideReadStories"

    /// Minimum comment count to surface a story in feeds. 0 = off.
    /// Hides drive-by submissions for users who only want stories
    /// with traction. Applies to the same feeds as hideReadStories.
    static let minStoryComments = "settings.minStoryComments"

    /// Comma-separated list of the user's most recent search queries
    /// (newest first, capped at 8). Surfaced as suggestions in the
    /// system `.searchable` field via `.searchSuggestions`.
    static let recentSearches = "settings.recentSearches"

    /// True once the user has either dismissed or acted on the
    /// "install an Enhanced voice" tip in NowPlayingView. Prevents
    /// the banner from re-appearing for users who chose to stick
    /// with the default voice.
    static let advancedVoiceTipDismissed = "settings.advancedVoiceTipDismissed"

    /// `AVSpeechSynthesisVoice.identifier` of the voice the user has
    /// explicitly chosen for TTS. Empty string = "auto" (SpoolPlayer
    /// picks the highest-quality voice matching the user's TTS
    /// language). Falls back to auto if the stored identifier no
    /// longer resolves — e.g., the user uninstalled the voice.
    static let voicePreferenceID = "settings.voicePreferenceID"

    /// True once the user has seen and dismissed the first-launch
    /// Apple Intelligence availability gate. Spool's headline
    /// features (summaries, audio queue) all require Apple
    /// Intelligence; the gate's job is to communicate that up front
    /// so a user without an eligible device or with AI disabled
    /// understands what's missing instead of finding broken-looking
    /// buttons. Once acknowledged, the gate doesn't re-appear even
    /// if AI later becomes available — the in-app states are clear
    /// enough on their own at that point.
    static let intelligenceGateSeen = "settings.intelligenceGateSeen"

    /// Whether the advanced (audio + Q&A) prompt editors are
    /// surfaced in Settings → Prompts. Hidden by default; users who
    /// want to tinker opt in via the toggle in the section.
    static let showAdvancedPrompts = "settings.showAdvancedPrompts"

    /// Comma-separated `HNStoryFeed` rawValues the user has chosen
    /// to hide from the sidebar's Categories section and the
    /// toolbar feed picker. Empty = show every feed. Stored as a
    /// joined string so it survives `@AppStorage`'s limited type
    /// support (no Set / [String] persistence out of the box).
    static let hiddenFeeds = "settings.hiddenFeeds"

    /// Whether the background mentions check schedules itself and
    /// fires notifications. `nil` (default) reads as enabled; users
    /// can flip it off explicitly from Settings. We don't ask iOS
    /// to revoke notification permission — just stop scheduling.
    static let mentionNotificationsEnabled = "settings.mentionNotificationsEnabled"
}
