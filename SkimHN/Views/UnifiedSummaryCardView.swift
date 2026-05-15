import SwiftUI

/// One card, two sections (Article + Discussion), one CTA. Replaces
/// the previous pair of separate "AI Summary" + "Thread Digest" cards
/// — those produced two buttons for one mental action and visually
/// stacked two glass panes for what users perceive as a single
/// "show me the AI take on this story" intent.
///
/// Owns both `SummaryViewModel` and `CommentsSummaryViewModel`. A
/// single Summarize tap fires them in parallel; each section streams
/// independently into its slot in the card. Sections are conditional
/// — articles without comments only render the Article section,
/// comments-only stories (Ask HN with no URL) only render Discussion.
struct UnifiedSummaryCardView: View {
    @ObservedObject var article: SummaryViewModel
    @ObservedObject var thread: CommentsSummaryViewModel
    let title: String
    let articleURL: URL?
    /// Lazily produced when the user taps Summarize so we don't pay
    /// the transcript-build cost for stories the user never asks about.
    let buildTranscript: () -> String
    let hasComments: Bool

    @Environment(\.openURL) private var openURL

    var body: some View {
        GroupBox {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack(spacing: 8) {
                Label("Summary", systemImage: "sparkles")
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(
                        .pulse,
                        options: .repeating,
                        isActive: isStreaming
                    )
                Spacer()
                statusBadge
            }
        }
    }

    // MARK: - Header / status

    private var isStreaming: Bool {
        articleIsStreaming || threadIsStreaming
    }

    private var articleIsStreaming: Bool {
        switch article.state {
        case .fetching, .streaming: return true
        default: return false
        }
    }

    private var threadIsStreaming: Bool {
        switch thread.state {
        case .streaming: return true
        default: return false
        }
    }

    private var hasAnyResult: Bool {
        articleHasResult || threadHasResult
    }

    private var articleHasResult: Bool {
        switch article.state {
        case .done, .streaming, .fetching, .error: return true
        default: return false
        }
    }

    private var threadHasResult: Bool {
        switch thread.state {
        case .done, .streaming, .error: return true
        default: return false
        }
    }

    private var canSummarize: Bool {
        article.canSummarize
    }

    private var canRunArticle: Bool {
        articleURL != nil
    }

    private var canRunThread: Bool {
        hasComments
    }

    @ViewBuilder
    private var statusBadge: some View {
        if !hasAnyResult {
            OutlineActionButton(title: "Summarize", systemImage: "sparkles") {
                runAll()
            }
            .disabled(!canSummarize || (!canRunArticle && !canRunThread))
        } else if !isStreaming {
            // Both done (or errored) — show a refresh.
            OutlineIconButton(
                systemImage: "arrow.clockwise",
                accessibilityLabel: "Summarize Again"
            ) {
                runAll()
            }
        } else {
            // Streaming — the pulsing sparkles in the header carry
            // the signal; no extra badge here keeps it calm.
            EmptyView()
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        if !hasAnyResult {
            promptText
        } else {
            VStack(alignment: .leading, spacing: 14) {
                if articleHasResult, canRunArticle {
                    articleSection
                }
                if articleHasResult && threadHasResult, canRunArticle, canRunThread {
                    Rectangle()
                        .fill(Color(.separator).opacity(0.5))
                        .frame(height: 0.5)
                        .padding(.vertical, 2)
                }
                if threadHasResult, canRunThread {
                    threadSection
                }
            }
        }
    }

    private var promptText: some View {
        Text(canSummarize
             ? promptCopy
             : article.availability.userMessage)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var promptCopy: String {
        switch (canRunArticle, canRunThread) {
        case (true, true):
            return "Tap Summarize for an on-device take on the article and the discussion."
        case (true, false):
            return "Tap Summarize for an on-device summary of the article."
        case (false, true):
            return "Tap Summarize for an on-device synthesis of the discussion."
        case (false, false):
            return "Nothing to summarize yet."
        }
    }

    // MARK: - Sections

    private var articleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Article")
            articleBody
        }
    }

    @ViewBuilder
    private var articleBody: some View {
        switch article.state {
        case .idle:
            EmptyView()
        case .fetching:
            SummaryPlaceholderLines()
        case .streaming:
            if article.text.isEmpty {
                SummaryPlaceholderLines()
            } else {
                Text(article.text)
                    .font(Theme.Typography.body)
                    .foregroundStyle(.primary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .done:
            MarkdownText(text: article.text)
                .textSelection(.enabled)
                .transition(.opacity)
        case .error(let message, let kind):
            articleError(message: message, kind: kind)
        }
    }

    @ViewBuilder
    private func articleError(message: String, kind: SummaryViewModel.FailureKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if kind == .guardrail {
                Text("Apple's on-device safety filter declined this content. Read the article directly instead.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if kind == .guardrail || kind == .contextOverflow, let url = articleURL {
                    OutlineActionButton(title: "Open Article", systemImage: "safari") {
                        openURL(url)
                    }
                }
                OutlineActionButton(title: "Retry", systemImage: "arrow.clockwise") {
                    runArticle()
                }
            }
        }
    }

    private var threadSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Discussion")
            threadBody
        }
    }

    @ViewBuilder
    private var threadBody: some View {
        switch thread.state {
        case .idle:
            EmptyView()
        case .streaming:
            if thread.text.isEmpty {
                SummaryPlaceholderLines()
            } else {
                Text(thread.text)
                    .font(Theme.Typography.body)
                    .foregroundStyle(.primary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .done:
            MarkdownText(text: thread.text)
                .textSelection(.enabled)
                .transition(.opacity)
        case .error(let message, let kind):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if kind == .guardrail {
                    Text("Comment threads can trip Apple's on-device safety filter. Scroll the thread below to read it manually.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if kind != .guardrail {
                    OutlineActionButton(title: "Try again", systemImage: "arrow.clockwise") {
                        runThread()
                    }
                }
            }
        }
    }

    private func sectionHeader(_ label: String) -> some View {
        Text(label)
            .font(.caption.weight(.heavy))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(Theme.accent)
    }

    // MARK: - Actions

    private func runAll() {
        runArticle()
        runThread()
    }

    private func runArticle() {
        guard canRunArticle, let url = articleURL else { return }
        article.summarize(title: title, url: url)
    }

    private func runThread() {
        guard canRunThread else { return }
        thread.summarize(title: title, transcript: buildTranscript())
    }
}
