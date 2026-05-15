import SwiftUI
import TipKit

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

    /// A runnable section is one we COULD summarize but haven't yet.
    /// E.g., a saved story with a cached article summary but no
    /// thread summary has `runnableThread = true` even though
    /// `hasAnyResult` is also true.
    private var runnableArticleIdle: Bool {
        guard canRunArticle else { return false }
        if case .idle = article.state { return true }
        return false
    }

    private var runnableThreadIdle: Bool {
        guard canRunThread else { return false }
        if case .idle = thread.state { return true }
        return false
    }

    private var anyRunnableIdle: Bool {
        runnableArticleIdle || runnableThreadIdle
    }

    @ViewBuilder
    private var statusBadge: some View {
        if isStreaming {
            // Pulsing sparkles in the header carry the signal — no
            // extra badge while content is streaming.
            EmptyView()
        } else if anyRunnableIdle {
            // Either fresh (nothing run) or partial (cached article,
            // thread not yet). Show "Summarize" — runs only the idle
            // sections, doesn't re-do the cached one.
            OutlineActionButton(title: "Summarize", systemImage: "sparkles") {
                runIdleSections()
            }
            .disabled(!canSummarize)
        } else if hasAnyResult {
            // Everything that can be summarized has been. Refresh
            // explicitly re-runs the lot.
            OutlineIconButton(
                systemImage: "arrow.clockwise",
                accessibilityLabel: "Summarize Again"
            ) {
                runAll()
            }
        } else {
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
                    articleSection(showHeader: showSubsectionHeaders)
                }
                if showSubsectionHeaders {
                    SummarySectionDivider()
                }
                if threadHasResult, canRunThread {
                    threadSection(showHeader: showSubsectionHeaders)
                }
            }
        }
    }

    /// Only label ARTICLE / DISCUSSION when both sub-summaries are
    /// actually rendering. With just one section visible, the card's
    /// own "Summary" header is sufficient and the sub-eyebrow would
    /// be a third stacked label for what reads as one block.
    private var showSubsectionHeaders: Bool {
        articleHasResult && threadHasResult && canRunArticle && canRunThread
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

    private func articleSection(showHeader: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if showHeader {
                sectionHeader("Article")
            }
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
                // Render markdown live so the user never sees raw
                // **asterisks** mid-stream; without this, the prose
                // jolts from raw markup to formatted output the moment
                // we flip to .done. StreamingDots gives a subtle "still
                // typing" tail at the bottom.
                VStack(alignment: .leading, spacing: 10) {
                    MarkdownText(text: article.text)
                    StreamingAuroraTrail()
                        .padding(.top, 2)
                }
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

    private func threadSection(showHeader: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if showHeader {
                sectionHeader("Discussion")
            }
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
                // Same live-markdown rendering as the article side —
                // discussion summaries lean on **Sentiment:** /
                // **Themes** patterns that look like literal noise in
                // plain Text.
                VStack(alignment: .leading, spacing: 10) {
                    MarkdownText(text: thread.text)
                    StreamingAuroraTrail()
                        .padding(.top, 2)
                }
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

    /// Re-run every section that has any result (and could run).
    /// Wired to the refresh icon when everything's been summarized.
    private func runAll() {
        runArticle()
        runThread()
    }

    /// Run only the sections still in `.idle`. Wired to the
    /// Summarize button so cached / already-streaming sections don't
    /// get clobbered when the user wants to fill in the missing
    /// side.
    private func runIdleSections() {
        Task { await SummarizeTip.summarizeTapped.donate() }
        if runnableArticleIdle { runArticle() }
        if runnableThreadIdle { runThread() }
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
