import SwiftUI

/// Sheet shown when the user taps Share on a story. Lets them
/// optionally bundle the AI article summary and/or the thread digest
/// with the URL — useful for pasting a story into Notes / Mail /
/// Messages with the rich context already attached.
///
/// Observes the same `SummaryViewModel` and `CommentsSummaryViewModel`
/// instances that `UnifiedSummaryCardView` does, so toggling an AI
/// option here:
///   - picks up the cached `.done` text instantly if the user already
///     summarized from the detail page, OR
///   - kicks off generation on the live VM right now, streaming into
///     this view's preview as tokens land.
struct ShareOptionsView: View {
    let title: String
    let url: URL?
    @ObservedObject var article: SummaryViewModel
    @ObservedObject var thread: CommentsSummaryViewModel
    /// Built lazily so we don't pay the transcript-flatten cost for
    /// stories the user never asks to summarize.
    let buildTranscript: () -> String
    let hasComments: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var includeURL: Bool = true
    @State private var includeArticleSummary: Bool = false
    @State private var includeThreadDigest: Bool = false

    private var aiAvailable: Bool {
        SummaryService.shared.isAvailable
    }

    private var canRunArticle: Bool {
        aiAvailable && url != nil
    }

    private var canRunThread: Bool {
        aiAvailable && hasComments
    }

    /// True once the article VM has produced something usable to
    /// include in the share payload.
    private var articleSummaryReady: Bool {
        guard case .done = article.state else { return false }
        return !article.text.isEmpty
    }

    private var threadDigestReady: Bool {
        guard case .done = thread.state else { return false }
        return !thread.text.isEmpty
    }

    private var articleIsGenerating: Bool {
        switch article.state {
        case .fetching, .streaming: return true
        default: return false
        }
    }

    private var threadIsGenerating: Bool {
        switch thread.state {
        case .streaming: return true
        default: return false
        }
    }

    private var anyGenerating: Bool {
        (includeArticleSummary && articleIsGenerating) ||
        (includeThreadDigest && threadIsGenerating)
    }

    var body: some View {
        NavigationStack {
            Form {
                includeSection
                previewSection
                shareSection
            }
            .navigationTitle("Share Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                includeURL = url != nil
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sections

    @ViewBuilder
    private var includeSection: some View {
        Section("Include") {
            Toggle(isOn: $includeURL) {
                Label("Article link", systemImage: "link")
            }
            .disabled(url == nil)
            .tint(Theme.accent)

            Toggle(isOn: includeArticleSummaryBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("AI summary", systemImage: "sparkles")
                    inlineStatus(
                        isGenerating: articleIsGenerating,
                        isReady: articleSummaryReady,
                        included: includeArticleSummary,
                        runnable: canRunArticle,
                        errorBinding: article.state
                    )
                }
            }
            .disabled(!canRunArticle)
            .tint(Theme.accent)

            Toggle(isOn: includeThreadDigestBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Thread digest", systemImage: "bubble.left.and.text.bubble.right.fill")
                    inlineStatus(
                        isGenerating: threadIsGenerating,
                        isReady: threadDigestReady,
                        included: includeThreadDigest,
                        runnable: canRunThread,
                        errorBinding: thread.state
                    )
                }
            }
            .disabled(!canRunThread)
            .tint(Theme.accent)
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        Section("Preview") {
            if let preview = composedText, !preview.isEmpty {
                Text(preview)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                Text("Pick at least one item to include.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var shareSection: some View {
        Section {
            if anyGenerating {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Generating…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else if let url, onlyURLSelected {
                // Real URL when only the link is selected so Messages
                // can render a rich link preview. Switching to String
                // for the bundled payloads is what keeps an "about:blank"
                // URL representation from leaking into text targets.
                ShareLink(item: url, preview: SharePreview(title)) {
                    shareButtonLabel
                }
                .listRowBackground(Theme.accent)
            } else if let composedText, !composedText.isEmpty {
                ShareLink(item: composedText, preview: SharePreview(title)) {
                    shareButtonLabel
                }
                .listRowBackground(Theme.accent)
            } else {
                Text("Pick at least one item to include.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Toggle bindings (kick off generation on flip)

    /// Custom binding so flipping the article toggle ON triggers
    /// `.summarize(...)` if the VM is idle. Without this, the user
    /// would have to summarize in the card first or the toggle would
    /// just include an empty payload.
    private var includeArticleSummaryBinding: Binding<Bool> {
        Binding {
            includeArticleSummary
        } set: { newValue in
            includeArticleSummary = newValue
            if newValue, canRunArticle, case .idle = article.state, let url {
                article.summarize(title: title, url: url)
            }
        }
    }

    private var includeThreadDigestBinding: Binding<Bool> {
        Binding {
            includeThreadDigest
        } set: { newValue in
            includeThreadDigest = newValue
            if newValue, canRunThread, case .idle = thread.state {
                thread.summarize(title: title, transcript: buildTranscript())
            }
        }
    }

    // MARK: - Inline status copy under each toggle

    @ViewBuilder
    private func inlineStatus(
        isGenerating: Bool,
        isReady: Bool,
        included: Bool,
        runnable: Bool,
        errorBinding: Any
    ) -> some View {
        if !runnable {
            // The toggle is .disabled in that case, so the user can't
            // flip it. Skip the inline status — the disabled control
            // tells the story.
            EmptyView()
        } else if included && isGenerating {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Generating…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if isReady {
            Text("Ready")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        // Idle + unincluded falls through to no caption — keeps
        // the row visually quiet when the user hasn't engaged yet.
    }

    // MARK: - Payload composition

    private var composedText: String? {
        var pieces: [String] = []
        if !title.isEmpty { pieces.append(title) }
        if includeURL, let url { pieces.append(url.absoluteString) }
        if includeArticleSummary, articleSummaryReady {
            pieces.append("AI summary:\n\(article.text)")
        }
        if includeThreadDigest, threadDigestReady {
            pieces.append("Thread digest:\n\(thread.text)")
        }
        guard !pieces.isEmpty else { return nil }
        pieces.append("Via SkimHN")
        return pieces.joined(separator: "\n\n")
    }

    private var onlyURLSelected: Bool {
        includeURL && !includeArticleSummary && !includeThreadDigest
    }

    private var shareButtonLabel: some View {
        Label("Share", systemImage: "square.and.arrow.up")
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white)
            .padding(.vertical, 4)
    }
}
