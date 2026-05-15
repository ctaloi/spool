import SwiftUI
import SwiftData
import SafariServices

struct StoryDetailView: View {
    @StateObject private var viewModel: StoryDetailViewModel
    @StateObject private var summary = SummaryViewModel()
    @StateObject private var commentsSummary = CommentsSummaryViewModel()
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.modelContext) private var modelContext
    @Query private var savedStories: [SavedStory]
    @State private var safariURL: PresentedURL?
    @State private var showLogin = false
    @State private var replyTarget: CommentNode?
    @State private var profileTarget: String?
    @State private var domainTarget: String?
    @State private var heroImage: UIImage?

    init(story: HNItem) {
        _viewModel = StateObject(wrappedValue: StoryDetailViewModel(story: story))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                commentsSection
            }
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .refreshable { await viewModel.loadComments(forceReload: true) }
        .navigationTitle(viewModel.story.host ?? "Story")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleSaved()
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .symbolEffect(.bounce, value: isSaved)
                        .contentTransition(.symbolEffect(.replace.downUp))
                }
                .accessibilityLabel(isSaved ? "Unsave Story" : "Save Story")
                .sensoryFeedback(.success, trigger: isSaved)
            }

            ToolbarItem(placement: .topBarTrailing) {
                if let urlString = viewModel.story.url, let url = URL(string: urlString) {
                    ShareLink(item: url)
                }
            }
        }
        .onAppear {
            // Detached from view lifecycle on purpose: NavigationSplitView
            // can briefly tear down the detail destination during its
            // push transition on compact width, which would cancel a
            // `.task`-attached load and leave us showing "No comments
            // yet". A plain Task runs to completion regardless.
            Task { @MainActor in
                await viewModel.loadComments()
                markAsRead()
            }
            // Hero image — independent of the thumbnail-in-list toggle.
            // The detail page is where the user explicitly opted into
            // the article, so the image is always welcome here.
            Task { @MainActor in
                await loadHeroImage()
            }
        }
        .sheet(item: $safariURL) { wrapped in
            SafariView(url: wrapped.url).ignoresSafeArea()
        }
        .sheet(isPresented: $showLogin) {
            LoginView().environmentObject(auth)
        }
        .sheet(item: $replyTarget) { target in
            ReplyView(
                parentID: target.id,
                parentAuthor: target.item.by,
                parentSnippet: snippet(from: target.item.text ?? "")
            )
            .environmentObject(auth)
        }
        .sheet(item: Binding(
            get: { profileTarget.map(IdentifiedUsername.init) },
            set: { profileTarget = $0?.value }
        )) { target in
            UserProfileView(username: target.value)
        }
        .sheet(item: Binding(
            get: { domainTarget.map(IdentifiedHost.init) },
            set: { domainTarget = $0?.value }
        )) { target in
            NavigationStack {
                AlgoliaFeedView(
                    kind: .domain(target.value),
                    navigationTitle: target.value,
                    navigationSubtitle: "Stories from \(target.value)",
                    navigationSystemImage: "globe"
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { domainTarget = nil }
                    }
                }
            }
            .environmentObject(auth)
        }
        .tint(Theme.accent)
    }

    private var isSaved: Bool {
        savedStories.contains { $0.id == viewModel.story.id }
    }

    /// Outline-only header chip — stroked capsule, no fill. Matches the
    /// AI summary card's outline buttons so the header reads as a quiet
    /// set of action affordances rather than a tinted toolbar.
    @ViewBuilder
    private func outlineChip(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.medium))
                .foregroundStyle(tint)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(tint.opacity(0.55), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Capsule(style: .continuous))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let heroImage, let urlString = viewModel.story.url, let url = URL(string: urlString) {
                Button {
                    safariURL = PresentedURL(url: url)
                } label: {
                    Image(uiImage: heroImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open article")
                .transition(.opacity)
            }

            Text(viewModel.story.title ?? "(no title)")
                .font(Theme.Typography.title)
                .fixedSize(horizontal: false, vertical: true)

            if let urlString = viewModel.story.url, let url = URL(string: urlString) {
                HStack(spacing: 8) {
                    outlineChip(
                        title: viewModel.story.host ?? urlString,
                        systemImage: "safari",
                        tint: Theme.accent
                    ) {
                        safariURL = PresentedURL(url: url)
                    }

                    if let host = viewModel.story.host {
                        outlineChip(
                            title: "Source",
                            systemImage: "rectangle.stack",
                            tint: .secondary
                        ) {
                            domainTarget = host
                        }
                        .accessibilityLabel("More from \(host)")
                    }
                }
            }

            if let text = viewModel.story.text, !text.isEmpty {
                HTMLText(html: text)
                    .padding(14)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10, style: .continuous))
            }

            if viewModel.story.type == "poll", let parts = viewModel.story.parts, !parts.isEmpty {
                PollView(parts: parts, showLogin: $showLogin)
                    .environmentObject(auth)
            }

            if let urlString = viewModel.story.url,
               let url = URL(string: urlString) {
                SummaryCardView(
                    viewModel: summary,
                    title: viewModel.story.title ?? "",
                    url: url
                )
            }

            HStack(spacing: 12) {
                VoteButton(
                    itemID: viewModel.story.id,
                    score: viewModel.story.score ?? 0,
                    showLogin: $showLogin
                )
                .environmentObject(auth)

                detailMetaLine

                Spacer(minLength: 0)
            }
        }
    }

    /// Quick HTML→plain-text strip for the reply sheet's parent preview.
    /// Doesn't need to be perfect; just readable.
    private func snippet(from html: String) -> String {
        var text = html
        text = text.replacingOccurrences(
            of: #"</(p|div|br)>"#,
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"),
            ("&nbsp;", " ")
        ]
        for (k, v) in entities {
            text = text.replacingOccurrences(of: k, with: v)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Best-effort OG image fetch for the article hero. Errors are
    /// swallowed — we just render no banner if the page has no
    /// `og:image` or the network refuses.
    private func loadHeroImage() async {
        guard let urlString = viewModel.story.url,
              let url = URL(string: urlString) else { return }
        do {
            let preview = try await ArticleFetcher.shared.fetchPreview(from: url)
            guard let imageURL = preview.imageURL else { return }
            let image = try await ImageFetcher.shared.image(for: imageURL)
            withAnimation(.easeInOut(duration: 0.25)) {
                heroImage = image
            }
        } catch {
            // Quiet failure — no banner.
        }
    }

    private func markAsRead() {
        let storyID = viewModel.story.id
        let descriptor = FetchDescriptor<ReadStory>(
            predicate: #Predicate { $0.id == storyID }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.readAt = .now
        } else {
            modelContext.insert(ReadStory(id: storyID))
        }
    }

    /// Flat meta line shown next to the vote button on the detail header:
    /// comments · author · time. Score lives inside the vote button.
    private var detailMetaLine: some View {
        HStack(spacing: 0) {
            if let count = viewModel.story.descendants {
                Text("^[\(count) comment](inflect: true)")
                    .monospacedDigit()
            }
            if let by = viewModel.story.by {
                metaSeparator
                Button {
                    profileTarget = by
                } label: {
                    Text(by)
                        .underline()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
                .buttonStyle(.plain)
            }
            if let date = viewModel.story.date {
                metaSeparator
                Text(date, format: .relative(presentation: .named))
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var metaSeparator: some View {
        Text(verbatim: "  ·  ")
            .foregroundStyle(.tertiary)
            .fixedSize()
    }

    @ViewBuilder
    private var commentsSection: some View {
        Label("\(viewModel.story.descendants ?? 0) Comments", systemImage: "bubble.left.and.bubble.right.fill")
            .font(Theme.Typography.sectionTitle)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)

        if let errorMessage = viewModel.errorMessage, viewModel.comments.isEmpty {
            VStack(spacing: 8) {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Button("Retry") {
                    Task { await viewModel.loadComments(forceReload: true) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Theme.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if viewModel.isLoading && viewModel.comments.isEmpty {
            HStack {
                Spacer()
                ProgressView().tint(Theme.accent)
                Spacer()
            }
            .padding(.vertical, 24)
        } else if viewModel.comments.isEmpty {
            Text("No comments yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
        } else {
            CommentsSummaryCardView(
                viewModel: commentsSummary,
                title: viewModel.story.title ?? "",
                transcript: { viewModel.commentsTranscript() }
            )
            .padding(.bottom, 12)

            // VStack (not LazyVStack) for the comment thread. Lazy view
            // recycling traps with brk #0x1 when expanding subtrees.
            // Eager rendering is slower on huge threads but correct, and
            // HN comment sections are bounded enough that it's fine.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.visibleComments) { node in
                    let collapsed = viewModel.collapsed.contains(node.id)
                    CommentView(
                        node: node,
                        isCollapsed: collapsed,
                        hiddenReplyCount: collapsed ? viewModel.hiddenReplyCount(for: node) : 0,
                        canReply: auth.isLoggedIn && !collapsed,
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                viewModel.toggleCollapse(node)
                            }
                        },
                        onReply: {
                            if auth.isLoggedIn {
                                replyTarget = node
                            } else {
                                showLogin = true
                            }
                        },
                        onSelectUser: { username in
                            profileTarget = username
                        }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func toggleSaved() {
        let story = viewModel.story
        if let existing = savedStories.first(where: { $0.id == story.id }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(SavedStory(
                id: story.id,
                title: story.title ?? "(untitled)",
                urlString: story.url,
                author: story.by,
                score: story.score,
                descendants: story.descendants
            ))
        }
    }
}

// MARK: - Safari sheet

private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: config)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private struct PresentedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Lets `sheet(item:)` use a plain String username.
private struct IdentifiedUsername: Identifiable {
    let value: String
    var id: String { value }
}

/// Same trick for a host name (domain feed sheet).
private struct IdentifiedHost: Identifiable {
    let value: String
    var id: String { value }
}
