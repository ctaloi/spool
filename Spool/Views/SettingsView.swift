import SwiftUI
import SwiftData

/// Settings sheet — all user-tunable preferences plus a couple of
/// developer-style "test" actions for the Mentions feature. Pushed
/// out of the sidebar (where it took up half the vertical space)
/// into a Form-based modal sheet, matching the AboutView pattern.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthViewModel
    @Query private var readStories: [ReadStory]

    @AppStorage(SettingsKeys.showAdvancedPrompts) private var showAdvancedPrompts: Bool = false
    @AppStorage(SettingsKeys.mentionNotificationsEnabled) private var mentionNotificationsEnabled: Bool = true

    @State private var showMarkAllUnreadConfirmation: Bool = false
    @State private var editingPrompt: SummaryPrompts.Key?

    var body: some View {
        NavigationStack {
            Form {
                displaySection
                voiceSection
                appleIntelligenceSection
                promptsSection
                if auth.isLoggedIn {
                    notificationsSection
                }
                librarySection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingPrompt) { key in
                PromptEditorView(key: key)
            }
        }
    }

    @ViewBuilder
    private var displaySection: some View {
        Section {
            NavigationLink {
                DisplaySettingsView()
            } label: {
                Label("Display", systemImage: "paintbrush")
            }
        } footer: {
            Text("Thumbnails, read-story hiding, minimum-comments filter, and which categories appear in the sidebar.")
        }
    }

    @ViewBuilder
    private var voiceSection: some View {
        Section {
            NavigationLink {
                VoicePickerView()
            } label: {
                Label("Voice", systemImage: "waveform")
            }
        } footer: {
            Text("Voice used for Spool audio. Switching applies to upcoming items — anything already playing finishes in the previous voice.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var appleIntelligenceSection: some View {
        switch SummaryService.shared.availability {
        case .available:
            EmptyView()
        case .appleIntelligenceDisabled:
            Section {
                Button {
                    if let url = URL(string: "App-prefs:Apple Intelligence") {
                        openURL(url)
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Apple Intelligence")
                                .foregroundStyle(.primary)
                            Text("Turn on in iOS Settings to unlock on-device summaries.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Theme.accent)
                    }
                }
            } header: {
                Text("Apple Intelligence")
            }
        case .modelNotReady:
            Section("Apple Intelligence") {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Intelligence preparing")
                            .foregroundStyle(.primary)
                        Text("Summarize buttons appear once the model finishes downloading.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    ProgressView().controlSize(.small)
                }
            }
        case .unsupportedDevice, .other:
            EmptyView()
        }
    }

    @ViewBuilder
    private var notificationsSection: some View {
        Section {
            Toggle(isOn: $mentionNotificationsEnabled) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mention Notifications")
                        Text("Notify me when someone replies to my comments.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "bell.badge")
                }
            }
            .tint(Theme.accent)
            .onChange(of: mentionNotificationsEnabled) { _, enabled in
                if enabled {
                    MentionsNotifier.scheduleNextRefresh()
                } else {
                    MentionsNotifier.cancelScheduledRefresh()
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Spool checks for new mentions in the background and posts a notification when any arrive. Toggle off to stop the background check entirely.")
        }
    }

    @ViewBuilder
    private var promptsSection: some View {
        Section {
            ForEach(basicPromptKeys) { key in
                promptRow(for: key)
            }
            Toggle(isOn: $showAdvancedPrompts) {
                Label("Show Advanced Prompts", systemImage: "slider.horizontal.3")
            }
            .tint(Theme.accent)
            if showAdvancedPrompts {
                ForEach(advancedPromptKeys) { key in
                    promptRow(for: key)
                }
            }
        } header: {
            Text("Prompts")
        } footer: {
            Text("Edit the on-device model's instructions. Defaults work well; tinker if you want a different summary style. Edits stay on your phone.")
        }
    }

    @ViewBuilder
    private func promptRow(for key: SummaryPrompts.Key) -> some View {
        Button {
            editingPrompt = key
        } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(key.displayName)
                        .foregroundStyle(.primary)
                    Text(key.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if SummaryPrompts.defaultHasMovedOn(key) {
                    Text("Default updated")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemBackground), in: .capsule)
                        .foregroundStyle(.secondary)
                        .overlay(
                            Capsule().stroke(Color(.separator), lineWidth: 0.5)
                        )
                } else if SummaryPrompts.isCustomized(key) {
                    Text("Customized")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accentSoft, in: .capsule)
                        .foregroundStyle(Theme.accent)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var basicPromptKeys: [SummaryPrompts.Key] {
        SummaryPrompts.Key.allCases.filter { $0.tier == .basic }
    }

    private var advancedPromptKeys: [SummaryPrompts.Key] {
        SummaryPrompts.Key.allCases.filter { $0.tier == .advanced }
    }

    @ViewBuilder
    private var librarySection: some View {
        Section {
            Button {
                showMarkAllUnreadConfirmation = true
            } label: {
                Label("Mark All as Unread", systemImage: "circle.badge.minus")
                    .foregroundStyle(.red)
            }
            .disabled(readStories.isEmpty)
            .confirmationDialog(
                "Mark all stories as unread?",
                isPresented: $showMarkAllUnreadConfirmation,
                titleVisibility: .visible
            ) {
                Button("Mark All as Unread", role: .destructive) {
                    clearReadHistory()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears the read state from every story you've opened. The list will look new again.")
            }
        } header: {
            Text("Library")
        } footer: {
            Text("\(readStories.count) read \(readStories.count == 1 ? "story" : "stories") tracked locally.")
        }
    }

    private func clearReadHistory() {
        for story in readStories {
            modelContext.delete(story)
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section {
            NavigationLink {
                AboutView()
            } label: {
                HStack {
                    Label("About", systemImage: "info.circle")
                    Spacer()
                    Text(Self.versionString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
