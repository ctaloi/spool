import SwiftUI

struct CommentsSummaryCardView: View {
    @ObservedObject var viewModel: CommentsSummaryViewModel
    let title: String
    let transcript: () -> String

    var body: some View {
        GroupBox {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                Label("Thread Digest", systemImage: "bubble.left.and.text.bubble.right.fill")
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

    private var isStreaming: Bool {
        if case .streaming = viewModel.state { return true }
        return false
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch viewModel.state {
        case .idle:
            OutlineActionButton(title: "Summarize", systemImage: "sparkles") {
                viewModel.summarize(title: title, transcript: transcript())
            }
            .disabled(!viewModel.canSummarize)
        case .streaming:
            ProgressBadge(text: "Reading thread…")
        case .done:
            OutlineIconButton(systemImage: "arrow.clockwise", accessibilityLabel: "Summarize Again") {
                viewModel.summarize(title: title, transcript: transcript())
            }
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            Text(viewModel.canSummarize
                 ? "Tap Summarize for a synthesis of the discussion."
                 : viewModel.availability.userMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .streaming:
            // Plain text while streaming — see SummaryCardView for
            // the rationale. Markdown formats in on completion.
            StreamingSummaryText(text: viewModel.text)
        case .done:
            MarkdownText(text: viewModel.text)
                .textSelection(.enabled)
                .transition(.opacity)
        case .error(let message, let kind):
            VStack(alignment: .leading, spacing: 10) {
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
                        viewModel.summarize(title: title, transcript: transcript())
                    }
                }
            }
        }
    }
}
