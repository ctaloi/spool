import SwiftUI

struct ReplyView: View {
    let parentID: Int
    let parentAuthor: String?
    let parentSnippet: String

    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var didSucceed = false
    @FocusState private var isTextFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !isSending
        && auth.isLoggedIn
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let author = parentAuthor {
                        Text(author)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Text(parentSnippet)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                } header: {
                    Text("Replying to")
                }

                Section("Reply") {
                    TextField("Write your reply…", text: $text, axis: .vertical)
                        .lineLimit(5...20)
                        .focused($isTextFocused)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if didSucceed {
                    Section {
                        Label("Reply posted.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Reply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Post") {
                            Task { await send() }
                        }
                        .fontWeight(.semibold)
                        .disabled(!canSend)
                    }
                }
            }
            .onAppear { isTextFocused = true }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSending)
    }

    private func send() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await HNAuthService.shared.reply(parentID: parentID, text: text)
            didSucceed = true
            try? await Task.sleep(for: .seconds(0.8))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
