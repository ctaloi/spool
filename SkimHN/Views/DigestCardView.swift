import SwiftUI

/// Inline catch-up card shown at the top of the Top Stories feed the
/// first time the user opens the app each day. Tappable to expand
/// (handled by the parent), dismissible per-day.
struct DigestCardView: View {
    @ObservedObject var viewModel: DigestViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Since you were away", systemImage: "sparkles")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.pulse, options: .repeating, isActive: isStreaming)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss catch-up")
            }

            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.accent.opacity(0.2), lineWidth: 1)
        )
    }

    private var isStreaming: Bool {
        if case .streaming = viewModel.state { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            Text("Drafting your catch-up…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .streaming:
            if viewModel.text.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.accent)
            } else {
                Text(viewModel.text)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .done:
            MarkdownText(text: viewModel.text)
                .transition(.opacity)
        case .error:
            // Fail quietly — catch-up isn't critical enough to surface.
            EmptyView()
        }
    }
}
