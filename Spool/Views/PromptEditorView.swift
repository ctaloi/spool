import SwiftUI

/// Full-screen editor for a single system prompt. Displays the
/// user's current text in a multi-line `TextEditor`, the bundled
/// default in a collapsed disclosure, and offers Reset / Save
/// actions. Reads/writes through `SummaryPrompts` so the
/// resolution layer stays the single source of truth.
struct PromptEditorView: View {
    let key: SummaryPrompts.Key
    @Environment(\.dismiss) private var dismiss

    @State private var draft: String = ""
    @State private var showResetConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    subtitleHeader
                    editor
                    defaultPreview
                    footerNotes
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle(key.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!hasChanges)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Label("Reset to Default", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(draft == key.defaultText)
                    Spacer()
                }
            }
            .confirmationDialog(
                "Reset to default?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset to Default", role: .destructive) {
                    draft = key.defaultText
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your customized prompt for \(key.displayName) will be replaced with the bundled default. You can edit again afterwards.")
            }
            .task(id: key) {
                // `.task(id:)` re-runs only when `key` changes, so we
                // don't need the previous `didLoad` flag to guard
                // against repeat seeding.
                draft = SummaryPrompts.resolved(key)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var subtitleHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if SummaryPrompts.isCustomized(key) {
                    Text("Customized")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accentSoft, in: .capsule)
                        .foregroundStyle(Theme.accent)
                }
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
                }
            }
        }
    }

    @ViewBuilder
    private var editor: some View {
        TextEditor(text: $draft)
            .font(.body.monospaced())
            .frame(minHeight: Theme.Layout.editorMinHeight)
            .scrollContentBackground(.hidden)
            .padding(10)
            .background(
                Color(.secondarySystemBackground),
                in: .rect(cornerRadius: Theme.CornerRadius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous)
                    .stroke(Color(.separator).opacity(0.5), lineWidth: 0.5)
            )
            .accessibilityLabel("\(key.displayName) prompt editor")
    }

    @ViewBuilder
    private var defaultPreview: some View {
        DisclosureGroup {
            Text(key.defaultText)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        } label: {
            Label("Default · tap to view", systemImage: "doc.text.magnifyingglass")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            Color(.tertiarySystemBackground),
            in: .rect(cornerRadius: Theme.CornerRadius.card, style: .continuous)
        )
    }

    @ViewBuilder
    private var footerNotes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("This prompt runs on-device. Edits stay on your phone.")
            } icon: {
                Image(systemName: "lock.shield")
                    .foregroundStyle(Theme.accent)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if key.tier == .advanced {
                Label {
                    Text(advancedFootnote)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    /// Tier-specific gotcha — surfaced for advanced prompts where
    /// edits can break the user experience in non-obvious ways.
    private var advancedFootnote: String {
        switch key {
        case .articleAudio, .commentsAudio:
            return "Audio prompts ask for plain prose. Adding markdown will make the text-to-speech engine read asterisks aloud."
        case .threadQA, .articleQA:
            return "Q&A prompts are constrained to the source text. Removing the grounding rule may produce speculative answers."
        case .article, .comments:
            return ""
        }
    }

    // MARK: - State

    private var hasChanges: Bool {
        let stored = SummaryPrompts.resolved(key)
        return draft != stored
    }

    private func save() {
        SummaryPrompts.setOverride(key, text: draft)
        dismiss()
    }
}
