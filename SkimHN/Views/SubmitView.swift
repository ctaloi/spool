import SwiftUI

struct SubmitView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var url = ""
    @State private var text = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var successID: Int?

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Required", text: $title, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    TextField("URL (optional)", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } footer: {
                    Text("Provide either a URL or text. Not both.")
                        .font(.caption2)
                }
                Section("Text (optional, for Ask HN)") {
                    TextField("", text: $text, axis: .vertical)
                        .lineLimit(4...12)
                }
                if let message = errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
                if let id = successID {
                    Section {
                        Label("Submitted! Item id=\(id)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("New Submission")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Submit").fontWeight(.semibold)
                        }
                    }
                    .disabled(isSubmitting || title.isEmpty || (url.isEmpty && text.isEmpty))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSubmitting)
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let id = try await HNAuthService.shared.submit(
                title: title,
                url: url.isEmpty ? nil : url,
                text: text.isEmpty ? nil : text
            )
            successID = id
            try? await Task.sleep(for: .seconds(1.5))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
