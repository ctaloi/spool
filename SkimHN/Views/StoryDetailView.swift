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
    @Query private var readLaterStories: [ReadLaterStory]
    /// Single piece of state driving every modal sheet on this view.
    /// Replaces seven separate `@State` flags whose combined surface
    /// area let two sheets race for presentation when bindings flipped
    /// in the same render pass.
    @State private var presentedSheet: DetailSheet?
    @State private var heroImage: UIImage?
    @State private var heroAccent: Color?
    /// `true` once we've finished asking the article for an OG image,
    /// regardless of outcome. Lets the hero banner show a pulsing
    /// skeleton while we're looking, then disappear cleanly when we
    /// learn the article has no image — instead of pulsing forever.
    @State private var heroLookupComplete: Bool = false
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    toggleReadLater()
                } label: {
                    Image(systemName: isQueued ? "checkmark.circle.fill" : "waveform.badge.plus")
                        .symbolEffect(.bounce, value: isQueued)
                        .contentTransition(.symbolEffect(.replace.downUp))
                }
                .accessibilityLabel(isQueued ? "Remove from Listen" : "Add to Listen")
                .sensoryFeedback(.success, trigger: isQueued)
                .keyboardShortcut("l", modifiers: .command)

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

                Button {
                    shareTapCount += 1
                    presentedSheet = .shareOptions
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .symbolEffect(.bounce, value: shareTapCount)
                }
                .accessibilityLabel("Share Story")
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .sensoryFeedback(.impact(weight: .light), trigger: shareTapCount)
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
        .sheet(item: $presentedSheet) { sheet in
            sheetDestination(for: sheet)
        }
        .tint(Theme.accent)
    }

    private var isSaved: Bool {
        savedStories.contains { $0.id == viewModel.story.id }
    }

    private var isQueued: Bool {
        readLaterStories.contains { $0.id == viewModel.story.id }
    }

    /// Bridges the consolidated `presentedSheet` state back to the
    /// `Binding<Bool>` shape that `VoteButton` and `PollView` expect
    /// for prompting login. Setting true flips presentedSheet to
    /// .login; setting false clears it only if .login was the
    /// currently-presented sheet (so we don't dismiss someone else's
    /// modal accidentally).
    private var showLoginBinding: Binding<Bool> {
        Binding(
            get: {
                guard case .login = presentedSheet else { return false }
                return true
            },
            set: { newValue in
                if newValue {
                    presentedSheet = .login
                } else if case .login = presentedSheet {
                    presentedSheet = nil
                }
            }
        )
    }

    /// Routes a `DetailSheet` value to its destination view. Single
    /// dispatch point for every modal — no two `.sheet` modifiers,
    /// no ambiguity about which boolean was set first when more than
    /// one event lands in the same render pass.
    @ViewBuilder
    private func sheetDestination(for sheet: DetailSheet) -> some View {
        switch sheet {
        case .safari(let url):
            SafariView(url: url).ignoresSafeArea()
        case .login:
            LoginView().environmentObject(auth)
        case .reply(let target):
            ReplyView(
                parentID: target.id,
                parentAuthor: target.item.by,
                parentSnippet: snippet(from: target.item.text ?? "")
            )
            .environmentObject(auth)
        case .profile(let username):
            UserProfileView(username: username)
        case .domain(let host):
            NavigationStack {
                AlgoliaFeedView(
                    kind: .domain(host),
                    navigationTitle: host,
                    navigationSubtitle: "Stories from \(host)",
                    navigationSystemImage: "globe"
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { presentedSheet = nil }
                    }
                }
            }
            .environmentObject(auth)
        case .threadQuestion:
            ThreadQuestionView(
                title: viewModel.story.title ?? "",
                transcript: viewModel.commentsTranscript()
            )
        case .shareOptions:
            ShareOptionsView(
                title: viewModel.story.title ?? "",
                url: viewModel.story.url.flatMap(URL.init(string:)),
                article: summary,
                thread: commentsSummary,
                buildTranscript: { viewModel.commentsTranscript() },
                hasComments: !viewModel.comments.isEmpty
            )
        }
    }

    /// Header chip — Liquid Glass on iOS 26. Same affordance, drawn
    /// by the system: translucent capsule, pressed state, motion.
    @ViewBuilder
    private func outlineChip(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .tint(tint)
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
                presentedSheet = .safari(url)
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
                        presentedSheet = .safari(url)
                    }

                    if let host = viewModel.story.host {
                        outlineChip(
                            title: "Source",
                            systemImage: "rectangle.stack",
                            tint: .secondary
                        ) {
                            presentedSheet = .domain(host)
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
                PollView(parts: parts, showLogin: showLoginBinding)
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
                    showLogin: showLoginBinding
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
                    presentedSheet = .profile(by)
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
                    presentedSheet = .threadQuestion
                } label: {
                    Label("Ask", systemImage: "questionmark.bubble")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .tint(Theme.accent)
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
                                presentedSheet = .reply(node)
                            } else {
                                presentedSheet = .login
                            }
                        },
                        onSelectUser: { username in
                            presentedSheet = .profile(username)
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
            SavedStoryIndexer.deindex(story.id)
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
            SavedStoryIndexer.index(saved)
        }
    }

    private func toggleReadLater() {
        let story = viewModel.story
        if let existing = readLaterStories.first(where: { $0.id == story.id }) {
            modelContext.delete(existing)
        } else {
            let nextPosition = (readLaterStories.map(\.position).max() ?? -1) + 1
            let queued = ReadLaterStory(
                id: story.id,
                title: story.title ?? "(untitled)",
                urlString: story.url,
                author: story.by,
                score: story.score,
                descendants: story.descendants,
                position: nextPosition
            )
            modelContext.insert(queued)
            // Pre-generate the article + thread summaries so the
            // playlist can stream audio without a network round-
            // trip when the user hits Play.
            SummaryPrefetcher.schedulePrefetch(for: queued, in: modelContext)
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

/// Discriminated union of every sheet the detail view can present.
/// Drives a single `.sheet(item:)` so two presentations can never
/// race for the same slot.
enum DetailSheet: Identifiable {
    case safari(URL)
    case login
    case reply(CommentNode)
    case profile(String)
    case domain(String)
    case threadQuestion
    case shareOptions

    var id: String {
        switch self {
        case .safari(let url):     return "safari:\(url.absoluteString)"
        case .login:               return "login"
        case .reply(let node):     return "reply:\(node.id)"
        case .profile(let user):   return "profile:\(user)"
        case .domain(let host):    return "domain:\(host)"
        case .threadQuestion:      return "threadQuestion"
        case .shareOptions:        return "shareOptions"
        }
    }
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

