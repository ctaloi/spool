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
                    if let payload = sharePayload {
                        ShareLink(
                            item: payload,
                            preview: SharePreview(title)
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(.white)
                                .padding(.vertical, 4)
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

    /// What we actually hand to ShareLink. When the user shares only
    /// the URL, pass the URL itself so apps like Messages render a
    /// rich link preview. When they share with extra context, pass a
    /// composed String — recipients see the full payload pasted in.
    private var sharePayload: SharePayload? {
        guard let composedText, !composedText.isEmpty else { return nil }
        let onlyURLSelected = includeURL && !includeArticleSummary && !includeThreadDigest
        if onlyURLSelected, let url {
            return .url(url)
        }
        return .text(composedText)
    }
}

/// Two-case Transferable wrapper so ShareLink can hand either a URL
/// or a composed String to the system share sheet, depending on what
/// the user toggled.
private enum SharePayload: Transferable {
    case url(URL)
    case text(String)

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { (payload: SharePayload) -> URL in
            if case .url(let url) = payload { return url }
            return URL(string: "about:blank")!
        }
        ProxyRepresentation { (payload: SharePayload) -> String in
            switch payload {
            case .url(let url): return url.absoluteString
            case .text(let text): return text
            }
        }
    }
}
