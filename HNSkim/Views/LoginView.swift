import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field { case user, pass }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sign in")
                                .font(.headline)
                            Text("Use your news.ycombinator.com credentials to vote and submit.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Credentials") {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .user)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .pass }

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .pass)
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                }

                if let message = auth.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if auth.isWorking {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Sign In")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(auth.isWorking || username.isEmpty || password.isEmpty)
                }

                Section {
                    Text("HN does not offer an official auth API, so credentials are sent directly to news.ycombinator.com over HTTPS and the session cookie is stored on this device only.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focusedField = .user }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(auth.isWorking)
    }

    private func submit() async {
        guard !username.isEmpty, !password.isEmpty else { return }
        let ok = await auth.login(username: username, password: password)
        if ok { dismiss() }
    }
}
