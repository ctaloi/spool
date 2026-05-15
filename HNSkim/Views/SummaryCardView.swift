import SwiftUI

struct SummaryCardView: View {
    @ObservedObject var viewModel: SummaryViewModel
    let title: String
    let url: URL
    @Environment(\.openURL) private var openURL

    var body: some View {
        GroupBox {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                Label("AI Summary", systemImage: "sparkles")
                    .foregroundStyle(Theme.accent)
                Spacer()
                statusBadge
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch viewModel.state {
        case .idle:
            OutlineActionButton(title: "Summarize", systemImage: "sparkles") {
                viewModel.summarize(title: title, url: url)
            }
            .disabled(!viewModel.canSummarize)
        case .fetching:
            ProgressBadge(text: "Reading article…")
        case .streaming:
            ProgressBadge(text: "Thinking…")
        case .done:
            OutlineIconButton(systemImage: "arrow.clockwise", accessibilityLabel: "Summarize Again") {
                viewModel.summarize(title: title, url: url)
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
                 ? "Tap Summarize for an on-device summary of the article."
                 : viewModel.availability.userMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)

        case .fetching:
            SummaryPlaceholderLines()

        case .streaming:
            if viewModel.text.isEmpty {
                SummaryPlaceholderLines()
            } else {
                MarkdownText(text: viewModel.text)
            }

        case .done:
            MarkdownText(text: viewModel.text)
                .textSelection(.enabled)

        case .error(let message, let kind):
            errorContent(message: message, kind: kind)
        }
    }

    @ViewBuilder
    private func errorContent(message: String, kind: SummaryViewModel.FailureKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if kind == .guardrail {
                Text("This is Apple's on-device safety filter — it can't be turned off. Read the article directly instead.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                switch kind {
                case .guardrail:
                    OutlineActionButton(title: "Open Article", systemImage: "safari") {
                        openURL(url)
                    }
                    OutlineActionButton(title: "Retry", systemImage: "arrow.clockwise") {
                        viewModel.summarize(title: title, url: url)
                    }
                case .contextOverflow:
                    OutlineActionButton(title: "Open Article", systemImage: "safari") {
                        openURL(url)
                    }
                case .other:
                    OutlineActionButton(title: "Try again", systemImage: "arrow.clockwise") {
                        viewModel.summarize(title: title, url: url)
                    }
                }
            }
        }
    }

}

struct SummaryPlaceholderLines: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.tertiary)
                    .frame(height: 10)
                    .frame(maxWidth: .infinity)
                    .padding(.trailing, CGFloat([0, 60, 120][index]))
            }
        }
        .accessibilityHidden(true)
    }
}

struct ProgressBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            ProgressView().controlSize(.mini)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Shared action affordance used by both summary cards. Outline-only —
/// the capsule is stroked, not filled, so the cards feel quiet alongside
/// the rest of the article view.
struct OutlineActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Theme.accent.opacity(0.55), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Capsule(style: .continuous))
    }
}

/// Icon-only outline variant — same stroked capsule, used for the
/// "Summarize Again" refresh affordance.
struct OutlineIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .overlay(
                    Circle().stroke(Theme.accent.opacity(0.55), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
