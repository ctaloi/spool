import SwiftUI

/// Sheet shown when the user taps Share on a story. Lets them
/// optionally bundle the AI article summary and/or the thread digest
/// with the URL — useful for pasting a story into Notes / Mail /
/// Messages with the rich context already attached.
struct ShareOptionsView: View {
    let title: String
    let url: URL?
    let articleSummary: String?
    let threadDigest: String?

    @Environment(\.dismiss) private var dismiss
    @State private var includeURL: Bool = true
    @State private var includeArticleSummary: Bool = false
    @State private var includeThreadDigest: Bool = false

    private var hasArticleSummary: Bool {
        guard let articleSummary else { return false }
        return !articleSummary.isEmpty
    }
    private var hasThreadDigest: Bool {
        guard let threadDigest else { return false }
        return !threadDigest.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Include") {
                    Toggle(isOn: $includeURL) {
                        Label("Article link", systemImage: "link")
                    }
                    .disabled(url == nil)
                    .tint(Theme.accent)

                    Toggle(isOn: $includeArticleSummary) {
                        Label("AI summary", systemImage: "sparkles")
                    }
                    .disabled(!hasArticleSummary)
                    .tint(Theme.accent)

                    Toggle(isOn: $includeThreadDigest) {
                        Label("Thread digest", systemImage: "bubble.left.and.text.bubble.right.fill")
                    }
                    .disabled(!hasThreadDigest)
                    .tint(Theme.accent)
                }

                Section {
                    if let preview = composedText, !preview.isEmpty {
                        Text(preview)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                } header: {
                    Text("Preview")
                }

                Section {
                    // Two distinct ShareLink shapes — pass a real URL
                    // when only the URL is selected so Messages can
                    // render a rich link preview, otherwise pass the
                    // composed String so Notes / Mail get the full
                    // payload. Never combine the two; an incorrect URL
                    // representation falling through to text targets
                    // would land "about:blank" in pasted content.
                    if let url, onlyURLSelected {
                        ShareLink(
                            item: url,
                            preview: SharePreview(title)
                        ) {
                            shareButtonLabel
                        }
                        .listRowBackground(Theme.accent)
                    } else if let composedText, !composedText.isEmpty {
                        ShareLink(
                            item: composedText,
                            preview: SharePreview(title)
                        ) {
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
            .navigationTitle("Share Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                // Default the URL toggle to whatever's available, but
                // leave the summary toggles off so the user explicitly
                // opts in to a heavier share payload.
                includeURL = url != nil
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// The composed text payload. Returns nil when nothing's selected
    /// so the Share button can disable itself.
    private var composedText: String? {
        var pieces: [String] = []

        if !title.isEmpty {
            pieces.append(title)
        }
        if includeURL, let url {
            pieces.append(url.absoluteString)
        }
        if includeArticleSummary, hasArticleSummary, let articleSummary {
            pieces.append("AI summary:\n\(articleSummary)")
        }
        if includeThreadDigest, hasThreadDigest, let threadDigest {
            pieces.append("Thread digest:\n\(threadDigest)")
        }

        guard !pieces.isEmpty else { return nil }
        // Trailing attribution so recipients know what app produced
        // the summary. Cheap brand surface, no friction.
        pieces.append("Via SkimHN")
        return pieces.joined(separator: "\n\n")
    }

    /// True when the user has the URL toggle on and nothing else —
    /// the case where we should hand a real URL to ShareLink so
    /// Messages renders a rich link preview.
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
