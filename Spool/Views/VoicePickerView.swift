import SwiftUI
import AVFoundation

/// Lets the user pin a specific `AVSpeechSynthesisVoice` for TTS, or
/// keep the default auto-pick (highest-quality voice matching the
/// user's TTS language). Persists the selection through
/// `SettingsKeys.voicePreferenceID` and tells the live `SpoolPlayer`
/// to invalidate its voice cache so the next utterance honors the
/// new choice.
///
/// Listed voices are filtered to drop novelty voices ("Bad News",
/// "Whisper", etc.) — fine for parlor tricks, wrong for spoken news
/// copy. The same filter `SpoolPlayer` applies for its auto-pick.
struct VoicePickerView: View {
    @EnvironmentObject private var player: SpoolPlayer
    @AppStorage(SettingsKeys.voicePreferenceID) private var preferenceID: String = ""
    @Environment(\.dismiss) private var dismiss

    /// Computed once when the view appears — `speechVoices()` is
    /// expensive AND noisy on the simulator. Re-fetched only if the
    /// user comes back via foreground transition (newly-installed
    /// voices) by way of the .onChange below.
    @State private var voicesByLanguage: [LanguageGroup] = []

    struct LanguageGroup: Identifiable {
        let id: String          // e.g., "en-US"
        let displayName: String // e.g., "English (United States)"
        let voices: [AVSpeechSynthesisVoice]
    }

    var body: some View {
        List {
            // Auto pick — clearing the preference returns to
            // SpoolPlayer's highest-quality-match behavior.
            Section {
                Button {
                    select(nil)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("System default")
                                .foregroundStyle(Color(.label))
                            Text("Highest-quality voice for your language")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if preferenceID.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }

            ForEach(voicesByLanguage) { group in
                Section(group.displayName) {
                    ForEach(group.voices, id: \.identifier) { voice in
                        Button {
                            select(voice.identifier)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(voice.name)
                                        .foregroundStyle(Color(.label))
                                    HStack(spacing: 6) {
                                        qualityPill(voice.quality)
                                        Text(voice.language)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if preferenceID == voice.identifier {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                }
            }

            // Cross-link to iOS's voice installer. iOS doesn't expose
            // a public deeplink straight to Voices, but App-prefs:
            // ACCESSIBILITY lands one step away and is what we already
            // use for the voice-tip banner.
            Section {
                Button {
                    openVoiceSettings()
                } label: {
                    HStack {
                        Label("Get more voices in iOS Settings", systemImage: "arrow.up.right.square")
                        Spacer()
                    }
                }
            } footer: {
                Text("Enhanced and Premium voices download from Settings → Accessibility → Spoken Content → Voices.")
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reloadVoices() }
    }

    private func qualityPill(_ quality: AVSpeechSynthesisVoiceQuality) -> some View {
        let label: String = {
            switch quality {
            case .premium:  return "Premium"
            case .enhanced: return "Enhanced"
            case .default:  return "Default"
            @unknown default: return "Default"
            }
        }()
        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(quality == .default ? Color.secondary : Theme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                (quality == .default ? Color(.tertiarySystemFill) : Theme.accent.opacity(0.12)),
                in: .capsule
            )
    }

    private func select(_ identifier: String?) {
        preferenceID = identifier ?? ""
        player.invalidateVoiceCache()
    }

    private func reloadVoices() {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            !voice.voiceTraits.contains(.isNoveltyVoice)
        }
        let grouped = Dictionary(grouping: voices, by: { $0.language })
        voicesByLanguage = grouped
            .map { language, voices in
                LanguageGroup(
                    id: language,
                    displayName: languageDisplayName(language),
                    voices: voices.sorted { a, b in
                        // Highest quality first, then alphabetical.
                        let qa = SpoolPlayer.qualityRank(a.quality)
                        let qb = SpoolPlayer.qualityRank(b.quality)
                        if qa != qb { return qa > qb }
                        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                    }
                )
            }
            // Put the device's current TTS language first; everything
            // else alphabetical by locale display name.
            .sorted { a, b in
                let target = AVSpeechSynthesisVoice.currentLanguageCode()
                if a.id == target { return true }
                if b.id == target { return false }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }
    }

    private func languageDisplayName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    /// Best-effort deep link to the Voices settings screen. iOS does
    /// not expose a public API for this — `App-prefs:ACCESSIBILITY`
    /// lands on the Accessibility root, one nav step away from
    /// Voices. Falls back to the app's own Settings page if the
    /// private URL is unavailable.
    private func openVoiceSettings() {
        let fallback = URL(string: UIApplication.openSettingsURLString)
        if let prefs = URL(string: "App-prefs:ACCESSIBILITY") {
            UIApplication.shared.open(prefs, options: [:]) { success in
                if !success, let fallback {
                    UIApplication.shared.open(fallback)
                }
            }
        } else if let fallback {
            UIApplication.shared.open(fallback)
        }
    }
}
