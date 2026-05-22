import SwiftUI

/// First-launch onboarding for users whose device doesn't have Apple
/// Intelligence available. Spool's headline features — story
/// summaries, comments digest, the audio queue — all require the
/// on-device language model. Without it, the app degrades into a
/// passable HN reader, but the marquee value is missing. This screen
/// communicates that *up front* so users with the wrong hardware or
/// the wrong toggle state don't install, tap Summarize, hit silent
/// failures, and leave a 1-star "doesn't work" review.
///
/// Copy is tailored per `SummaryAvailability` case so a user with an
/// eligible device but the toggle off sees an actionable
/// "Open Settings" CTA, while a user with an A16 iPhone sees an
/// honest "this device can't run on-device AI" — different problems,
/// different right answers.
struct AppleIntelligenceGateView: View {
    let availability: SummaryAvailability
    @Binding var isPresented: Bool
    @AppStorage(SettingsKeys.intelligenceGateSeen) private var seen: Bool = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    icon
                        .padding(.top, 24)
                        .frame(maxWidth: .infinity, alignment: .center)

                    VStack(alignment: .leading, spacing: 14) {
                        Text(title)
                            .font(.system(size: 30, weight: .semibold))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(explanation)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !worksWithoutAI.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("What still works without it")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.5)
                            ForEach(worksWithoutAI, id: \.self) { line in
                                Label {
                                    Text(line).foregroundStyle(.primary)
                                } icon: {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.accent)
                                }
                                .font(.callout)
                            }
                        }
                        .padding(16)
                        .background(
                            Color(.secondarySystemBackground),
                            in: .rect(cornerRadius: Theme.CornerRadius.card, style: .continuous)
                        )
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }

            VStack(spacing: 12) {
                if let action = primaryAction {
                    Button {
                        action.perform(openURL)
                        dismiss()
                    } label: {
                        Text(action.title)
                            .font(.headline)
                            .foregroundStyle(Color(.systemBackground))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Color(.label),
                                in: .rect(cornerRadius: 999, style: .continuous)
                            )
                    }
                }
                Button {
                    dismiss()
                } label: {
                    Text(secondaryActionTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    // MARK: - Copy

    private var icon: some View {
        Image(systemName: iconName)
            .font(.system(size: 56, weight: .light))
            .foregroundStyle(Theme.accent)
            .frame(width: 96, height: 96)
            .background(
                Theme.accent.opacity(0.12),
                in: .rect(cornerRadius: 24, style: .continuous)
            )
    }

    private var iconName: String {
        switch availability {
        case .appleIntelligenceDisabled: return "sparkles"
        case .modelNotReady:             return "arrow.down.circle"
        case .unsupportedDevice:         return "iphone.gen3"
        case .other, .available:         return "sparkles"
        }
    }

    private var title: String {
        switch availability {
        case .appleIntelligenceDisabled:
            return "Turn on Apple Intelligence"
        case .modelNotReady:
            return "Apple Intelligence is downloading"
        case .unsupportedDevice:
            return "This device can't run Spool's AI features"
        case .other, .available:
            return "Apple Intelligence isn't available"
        }
    }

    private var explanation: String {
        switch availability {
        case .appleIntelligenceDisabled:
            return "Spool's summaries and audio queue run on your phone's on-device language model. To use them, enable Apple Intelligence in iOS Settings — it's a one-time switch and the model downloads in the background."
        case .modelNotReady:
            return "iOS is still installing the on-device language model. Spool's AI features will light up automatically once it finishes — you can keep browsing HN in the meantime."
        case .unsupportedDevice:
            return "Spool's summaries and audio queue need Apple Intelligence, which only runs on iPhone 15 Pro and newer. You can still use Spool as a clean HN reader on this device, but the headline AI features won't be available."
        case .other(let message):
            return message
        case .available:
            return ""
        }
    }

    private var worksWithoutAI: [String] {
        switch availability {
        case .available:
            return []
        default:
            return [
                "Every HN feed: Top, New, Best, Ask, Show, Jobs",
                "Search and Best-of windows",
                "Sign in to vote, post, and reply",
                "Saved stories, threaded comments with Q&A disabled",
                "Configurable home-screen widget",
            ]
        }
    }

    // MARK: - Actions

    private struct GateAction {
        let title: String
        let perform: (_ openURL: OpenURLAction) -> Void
    }

    private var primaryAction: GateAction? {
        switch availability {
        case .appleIntelligenceDisabled:
            return GateAction(title: "Open iOS Settings") { openURL in
                openURL(URL(string: "App-prefs:Apple Intelligence")!) { success in
                    if !success {
                        openURL(URL(string: UIApplication.openSettingsURLString)!)
                    }
                }
            }
        case .unsupportedDevice, .modelNotReady, .other, .available:
            return nil
        }
    }

    private var secondaryActionTitle: String {
        switch availability {
        case .appleIntelligenceDisabled, .modelNotReady, .other:
            return "Continue without AI features for now"
        case .unsupportedDevice:
            return "Continue to the HN reader"
        case .available:
            return "Dismiss"
        }
    }

    private func dismiss() {
        seen = true
        withAnimation(.easeInOut(duration: Theme.AnimationDuration.standard)) {
            isPresented = false
        }
    }
}
