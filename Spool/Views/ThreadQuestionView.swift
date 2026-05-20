import SwiftUI

/// "Ask the thread" — type a question about the discussion, get an
/// on-device answer grounded in the comments. Same Foundation Models
/// pipeline as our summaries; new prompt, same private + offline-ish
/// properties.
struct ThreadQuestionView: View {
    let title: String
    let transcript: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = ThreadQuestionViewModel()
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro

                    questionField

                    answerBlock
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .navigationTitle("Ask the Thread")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .background(Color(.systemBackground))
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { fieldFocused = true }
    }

    private var intro: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "questionmark.bubble")
                .font(.title3)
                .foregroundStyle(Theme.accent)
            Text("Ask anything about this discussion. Answers come from the comments on-device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var questionField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField(
                    "e.g. What's the consensus on Proton Mail's limits?",
                    text: $vm.question,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($fieldFocused)
                .submitLabel(.send)
                .onSubmit { vm.ask(title: title, transcript: transcript) }
                .autocorrectionDisabled()

                if !vm.question.isEmpty {
                    Button {
                        vm.ask(title: title, transcript: transcript)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                    }
                    .disabled(!vm.canAnswer)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel("Ask")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: Capsule(style: .continuous))

            if !vm.canAnswer {
                Text(vm.availability.userMessage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var answerBlock: some View {
        switch vm.state {
        case .idle:
            EmptyView()
        case .streaming:
            VStack(alignment: .leading, spacing: 6) {
                Label("Thinking…", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.pulse, options: .repeating, isActive: true)
                if !vm.text.isEmpty {
                    Text(vm.text)
                        .font(Theme.Typography.body)
                        .foregroundStyle(.primary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .done:
            MarkdownText(text: vm.text)
                .textSelection(.enabled)
                .transition(.opacity)
        case .error(let message, _):
            VStack(alignment: .leading, spacing: 8) {
                Text("Couldn't answer that")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
