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
    @State private var heroAccent: Color?
    /// `true` once we've finished asking the article for an OG image,
    /// regardless of outcome. Lets the hero banner show a pulsing
    /// skeleton while we're looking, then disappear cleanly when we
    /// learn the article has no image — instead of pulsing forever.
    @State private var heroLookupComplete: Bool = false
    @State private var showThreadQuestion: Bool = false
    @State private var showShareOptions: Bool = false
    /// Bumps each time the user taps Share — keyed by the symbol-
    /// effect so the icon only bounces on press, never on close.
    @State private var shareTapCount: Int = 0

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
        // Tint the navbar's glass material with the story's dominant
        // color. Subtle (low-opacity material) — the navbar still reads
        // as standard chrome but each story carries a hint of its
        // source's brand. Animated so it settles in once we've
        // extracted the color from the hero image.
        .toolbarBackground(
            heroAccent.map { $0.opacity(0.22) } ?? Color.clear,
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .animation(.easeInOut(duration: 0.5), value: heroAccent)
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
                .keyboardShortcut("s", modifiers: .command)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shareTapCount += 1
                    showShareOptions = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .symbolEffect(.bounce, value: shareTapCount)
                }
                .accessibilityLabel("Share Story")
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .sensoryFeedback(.impact(weight: .light), trigger: shareTapCount)
            }

            // Cmd+O / Cmd+Return — open the article in Safari without
            // having to scroll back to the header chip.
            ToolbarItem(placement: .topBarTrailing) {
                if let urlString = viewModel.story.url, let url = URL(string: urlString) {
                    Button {
                        safariURL = PresentedURL(url: url)
                    } label: {
                        Image(systemName: "safari")
                    }
                    .accessibilityLabel("Open Article")
                    .keyboardShortcut("o", modifiers: .command)
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
            Task { @MainActor in
                await loadHeroImage()
            }
            adoptCachedSummaryIfAvailable()
        }
        // If the prefetcher writes a cached summary *while* the detail
        // is open (e.g., user saved + opened in quick succession),
        // the @Query update fires here and we adopt the cache without
        // the user needing to close + reopen the view.
        .onChange(of: savedStories.first(where: { $0.id == viewModel.story.id })?.cachedSummaryText) { _, _ in
            adoptCachedSummaryIfAvailable()
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
        .sheet(isPresented: $showThreadQuestion) {
            ThreadQuestionView(
                title: viewModel.story.title ?? "",
                transcript: viewModel.commentsTranscript()
            )
        }
        .sheet(isPresented: $showShareOptions) {
            ShareOptionsView(
                title: viewModel.story.title ?? "",
                url: viewModel.story.url.flatMap(URL.init(string:)),
                articleSummary: shareableArticleSummary,
                threadDigest: shareableThreadDigest
            )
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

    /// Hero banner. Three states:
    /// 1. Article has no URL → no banner.
    /// 2. Lookup in flight (no image yet, not yet finished) → pulsing
    ///    skeleton in the source's brand tint (if we know it) or neutral.
    /// 3. Lookup finished:
    ///    - Image present → render it with a soft bottom gradient.
    ///    - No image present → banner hides entirely (no awkward
    ///      forever-pulsing skeleton for sites that don't ship OG tags).
    @ViewBuilder
    private var heroBanner: some View {
        if let urlString = viewModel.story.url,
           let url = URL(string: urlString),
           shouldShowHero {
            Button {
                safariURL = PresentedURL(url: url)
            } label: {
                Rectangle()
                    .fill(skeletonColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .overlay {
                        if let heroImage {
                            Image(uiImage: heroImage)
                                .resizable()
                                .scaledToFill()
                                .transition(.opacity)
                        } else {
                            HeroSkeleton(tint: heroAccent ?? Theme.accent)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if heroImage != nil {
                            LinearGradient(
                                colors: [Color.clear, Color(.systemBackground).opacity(0.45)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                            .frame(height: 80)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke((heroAccent ?? Color(.separator)).opacity(heroAccent == nil ? 0.4 : 0.35), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open article")
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// True while we're still looking for an OG image, OR after we've
    /// found one. False once we've finished looking and confirmed the
    /// article has none — so the placeholder doesn't linger forever on
    /// image-less articles (changelogs, status pages, repos, etc).
    private var shouldShowHero: Bool {
        if heroImage != nil { return true }
        return !heroLookupComplete
    }

    /// Tinted-toward-the-source skeleton color while the hero loads. We
    /// hint at the dominant color once we've got it; otherwise default
    /// to a neutral system fill so the placeholder doesn't draw the eye.
    private var skeletonColor: Color {
        if let heroAccent {
            return heroAccent.opacity(0.18)
        }
        return Color(.tertiarySystemFill)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            heroBanner

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

            // Unified Article + Discussion summary card — replaces the
            // old pair of separate cards so the user sees one CTA
            // instead of two stacked Summarize buttons.
            UnifiedSummaryCardView(
                article: summary,
                thread: commentsSummary,
                title: viewModel.story.title ?? "",
                articleURL: viewModel.story.url.flatMap(URL.init(string:)),
                buildTranscript: { viewModel.commentsTranscript() },
                hasComments: !viewModel.comments.isEmpty
            )

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
    /// `og:image` or the network refuses. Also pulls the dominant
    /// color out of the image so we can tint the skeleton/gradient.
    /// The AI article summary in shareable form — present only after a
    /// successful generation, or when a saved-story prefetch has
    /// cached one. Returns nil otherwise so the Share sheet's toggle
    /// stays disabled.
    private var shareableArticleSummary: String? {
        if case .done = summary.state, !summary.text.isEmpty {
            return summary.text
        }
        if let saved = savedStories.first(where: { $0.id == viewModel.story.id }),
           let cached = saved.cachedSummaryText, !cached.isEmpty {
            return cached
        }
        return nil
    }

    /// Same for the comment-thread digest. Only available once the
    /// digest has streamed to .done.
    private var shareableThreadDigest: String? {
        if case .done = commentsSummary.state, !commentsSummary.text.isEmpty {
            return commentsSummary.text
        }
        return nil
    }

    /// Adopt the saved record's pre-generated summary if it's available
    /// AND the user hasn't already triggered a live summarize. The
    /// `.idle` guard prevents us from stomping on an in-flight stream
    /// the user just kicked off manually.
    private func adoptCachedSummaryIfAvailable() {
        guard case .idle = summary.state else { return }
        guard let saved = savedStories.first(where: { $0.id == viewModel.story.id }),
              let cached = saved.cachedSummaryText,
              !cached.isEmpty
        else { return }
        _ = summary.loadCachedIfAvailable(cached)
    }

    private func loadHeroImage() async {
        guard let urlString = viewModel.story.url,
              let url = URL(string: urlString) else {
            heroLookupComplete = true
            return
        }
        defer {
            // Whether we succeeded, errored, or got nothing back, the
            // skeleton needs to stop pulsing. Animate so the banner
            // either fades to the loaded image or fades away entirely.
            withAnimation(.easeInOut(duration: 0.3)) {
                heroLookupComplete = true
            }
        }
        do {
            let preview = try await ArticleFetcher.shared.fetchPreview(from: url)
            guard let imageURL = preview.imageURL else { return }
            let image = try await ImageFetcher.shared.image(for: imageURL)
            withAnimation(.easeInOut(duration: 0.5)) {
                heroImage = image
            }
            if let extracted = await DominantColor.shared.extract(from: image, url: imageURL) {
                withAnimation(.easeInOut(duration: 0.35)) {
                    heroAccent = Color(extracted)
                }
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
        HStack(spacing: 8) {
            Label("\(viewModel.story.descendants ?? 0) Comments", systemImage: "bubble.left.and.bubble.right.fill")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(.secondary)
            Spacer()
            if !viewModel.comments.isEmpty {
                Button {
                    showThreadQuestion = true
                } label: {
                    Label("Ask", systemImage: "questionmark.bubble")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Theme.accent.opacity(0.55), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ask a question about this thread")
            }
        }
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
            // The Discussion section now lives inside the unified
            // summary card in the header — no standalone digest card
            // here anymore.

            // LazyVStack — only the visible comment window renders, so
            // big threads (500+) scroll smoothly instead of freezing on
            // initial layout. The historical `brk #0x1` trap from
            // dynamic-range ForEach inside CommentView is already
            // defended against via the fixed `depthLevels` array, and
            // stable `CommentNode.id` (Identifiable) keeps SwiftUI from
            // recycling rows across different nodes.
            LazyVStack(alignment: .leading, spacing: 0) {
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
            let saved = SavedStory(
                id: story.id,
                title: story.title ?? "(untitled)",
                urlString: story.url,
                author: story.by,
                score: story.score,
                descendants: story.descendants
            )
            modelContext.insert(saved)
            SummaryPrefetcher.schedulePrefetch(for: saved, in: modelContext)
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

/// Quiet pulsing placeholder shown in the hero banner while the OG
/// image is fetching. A single faint highlight band sweeps left→right
/// on a 1.6s cycle — slow enough to read as "loading" without drawing
/// attention to itself.
private struct HeroSkeleton: View {
    let tint: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = (sin(t * 2.0 * .pi / 1.8) + 1.0) / 2.0
            ZStack {
                tint.opacity(0.16)
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: max(0.0, phase - 0.25)),
                        .init(color: tint.opacity(0.32), location: phase),
                        .init(color: .clear, location: min(1.0, phase + 0.25)),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .accessibilityHidden(true)
    }
}

/// Same trick for a host name (domain feed sheet).
private struct IdentifiedHost: Identifiable {
    let value: String
    var id: String { value }
}
