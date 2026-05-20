import SwiftUI
import FoundationModels

/// SwiftUI host for the Share Extension's summary UI. Self-contained:
/// the extension can't easily depend on the main app's modules without
/// pulling everything in, so we inline a tiny article fetcher + a
/// thin wrapper around LanguageModelSession here.
struct ShareSummaryView: View {
    let url: URL?
    let onDismiss: () -> Void

    @State private var state: ExtensionState = .idle
    @State private var summary: String = ""

    enum ExtensionState {
        case idle
        case fetching
        case streaming
        case done
        case unavailable(String)
        case error(String)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let url {
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                                .foregroundStyle(.secondary)
                            Text(url.host ?? url.absoluteString)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    content
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .navigationTitle("AI Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDismiss)
                }
            }
            .task {
                if let url {
                    await run(url: url)
                } else {
                    state = .error("Couldn't read a URL from the share.")
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            Color.clear.frame(height: 1)
        case .fetching:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Reading article…").font(.footnote).foregroundStyle(.secondary)
            }
        case .streaming, .done:
            Text(summary)
                .font(.body)
                .lineSpacing(5)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        case .unavailable(let why):
            Text(why).font(.footnote).foregroundStyle(.secondary)
        case .error(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text("Couldn't summarize")
                    .font(.subheadline.weight(.semibold))
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @MainActor
    private func run(url: URL) async {
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let reason):
            state = .unavailable("On-device AI isn't available: \(reason)")
            return
        }

        state = .fetching
        do {
            let html = try await fetchHTML(url: url)
            let text = strip(html: html).prefix(5_000)
            guard !text.isEmpty else {
                state = .error("Couldn't extract article text.")
                return
            }
            state = .streaming
            summary = ""

            let session = LanguageModelSession(instructions: instructions)
            let prompt = "Article URL: \(url.absoluteString)\n\nArticle text:\n\(text)"
            let stream = session.streamResponse(to: prompt)
            for try await partial in stream {
                summary = partial.content
            }
            state = .done
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private var instructions: String {
        """
        You are a concise summarizer. Read the provided article text and produce:
        - TL;DR — one sentence.
        - 3–5 short bullets of the most important facts.
        Use only the provided text. Neutral tone. No links.
        """
    }

    private func fetchHTML(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605 (KHTML, like Gecko) Version/17 Safari/605",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: request)
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    /// Minimal HTML→text — extension doesn't share code with the main
    /// app, so we inline a stripped-down version of ArticleFetcher's
    /// regex chain.
    private func strip(html: String) -> String {
        var t = html
        let kill = [
            #"<script[^>]*>[\s\S]*?</script>"#,
            #"<style[^>]*>[\s\S]*?</style>"#,
            #"<noscript[^>]*>[\s\S]*?</noscript>"#,
            #"<!--[\s\S]*?-->"#,
            #"<svg[^>]*>[\s\S]*?</svg>"#,
        ]
        for p in kill { t = t.replacingOccurrences(of: p, with: " ", options: .regularExpression) }
        t = t.replacingOccurrences(of: #"</(p|div|section|article|li|h[1-6]|br|tr)>"#, with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        for (k, v) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")] {
            t = t.replacingOccurrences(of: k, with: v)
        }
        t = t.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
