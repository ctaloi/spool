import Foundation

@MainActor
final class SummaryViewModel: ObservableObject {
    enum FailureKind {
        /// Apple's on-device guardrail declined the input or output.
        /// Can't be bypassed; UI offers an "Open Article" fallback.
        case guardrail
        /// Article still overflows the context window at the minimum budget.
        case contextOverflow
        /// Anything else — generic retry.
        case other
    }

    enum State {
        case idle
        case fetching
        case streaming
        case done
        case error(message: String, kind: FailureKind)
    }

    @Published private(set) var state: State = .idle
    /// The text the view actually renders. Driven by a steady-cadence
    /// drain ticker, not by the raw model stream — so the UI sees text
    /// arrive at a consistent reading pace even when Foundation Models
    /// bursts a paragraph at once or stalls for half a second.
    @Published private(set) var text: String = ""

    private var task: Task<Void, Never>?
    private var drainTask: Task<Void, Never>?
    /// Latest cumulative text from the model. The drain ticker pulls
    /// from here into `text` one word at a time. Not published — the
    /// view only cares about `text`. Stored in a plain var because the
    /// drain task reads it on the main actor anyway.
    private var fullText: String = ""
    /// Set when the upstream stream completes (success path). The drain
    /// loop uses this to decide when to flip to `.done`.
    private var streamFinished: Bool = false

    /// Steady cadence between word reveals during the drain. ~25 words/
    /// second — feels like a writer pacing themselves, not a typewriter.
    private let baseWordInterval: Duration = .milliseconds(40)
    /// Compressed cadence when the buffer is way ahead — keeps us from
    /// holding stale text for seconds after the model finishes a big run.
    private let fastWordInterval: Duration = .milliseconds(15)
    /// Backlog (chars not yet displayed) above which we kick into the
    /// fast cadence.
    private let fastDrainBacklog: Int = 150

    var availability: SummaryAvailability { SummaryService.shared.availability }

    var canSummarize: Bool {
        if case .available = availability { return true }
        return false
    }

    /// If we've already pre-generated a summary for this story (from
    /// the SummaryPrefetcher fired on save), short-circuit straight to
    /// the formatted markdown render. Instant + works offline.
    func loadCachedIfAvailable(_ cachedText: String?) -> Bool {
        guard let cachedText, !cachedText.isEmpty else { return false }
        cancel()
        text = cachedText
        fullText = cachedText
        streamFinished = true
        state = .done
        return true
    }

    func summarize(title: String, url: URL) {
        cancel()
        text = ""
        fullText = ""
        streamFinished = false
        state = .fetching

        task = Task { [weak self] in
            guard let self else { return }

            // Apple's on-device model has a ~4K-token context window. Long
            // articles overflow, so we start conservative and halve on
            // overflow until the model accepts or we hit the floor.
            var charBudget = 6_000
            let minBudget = 1_500

            while true {
                do {
                    let article = try await ArticleFetcher.shared
                        .fetchText(from: url, maxCharacters: charBudget)
                    guard !article.isEmpty else {
                        self.state = .error(
                            message: SummaryError.emptyArticle.localizedDescription,
                            kind: .other
                        )
                        return
                    }

                    self.text = ""
                    self.fullText = ""
                    self.streamFinished = false
                    self.state = .streaming
                    self.startDrain()
                    let stream = SummaryService.shared.summarize(
                        title: title,
                        articleText: article
                    )
                    for try await partial in stream {
                        if Task.isCancelled { return }
                        self.fullText = partial
                    }
                    if !Task.isCancelled {
                        // Mark the stream done — drain loop will flip
                        // state to .done once the visible cursor catches
                        // up with the full buffer.
                        self.streamFinished = true
                    }
                    return
                } catch is CancellationError {
                    return
                } catch {
                    let classified = SummaryError.classify(error)
                    switch classified {
                    case .contextTooLong where charBudget > minBudget:
                        charBudget = max(minBudget, charBudget / 2)
                        self.state = .fetching
                        continue
                    case .contextTooLong:
                        self.state = .error(
                            message: classified.localizedDescription,
                            kind: .contextOverflow
                        )
                    case .guardrail:
                        self.state = .error(
                            message: classified.localizedDescription,
                            kind: .guardrail
                        )
                    default:
                        self.state = .error(
                            message: classified.localizedDescription,
                            kind: .other
                        )
                    }
                    self.cancelDrain()
                    return
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        cancelDrain()
        streamFinished = false
        fullText = ""
    }

    /// Drain `fullText` into `text` one word boundary at a time. Runs
    /// for the duration of the stream and a tail beyond — exits once
    /// upstream is done and the visible cursor has caught up.
    private func startDrain() {
        cancelDrain()
        drainTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                let full = self.fullText
                let shownCount = self.text.count
                let fullCount = full.count

                if shownCount < fullCount {
                    let nextCount = Self.nextWordBoundary(
                        in: full,
                        afterCount: shownCount
                    )
                    self.text = String(full.prefix(nextCount))

                    let backlog = fullCount - nextCount
                    let interval: Duration = backlog > self.fastDrainBacklog
                        ? self.fastWordInterval
                        : self.baseWordInterval
                    try? await Task.sleep(for: interval)
                } else if self.streamFinished {
                    // Caught up and upstream is done — snap state to
                    // .done so the formatted MarkdownText takes over.
                    self.state = .done
                    return
                } else {
                    // Caught up but model is still working. Idle in
                    // short hops so we react quickly when more text
                    // arrives without spinning the CPU.
                    try? await Task.sleep(for: .milliseconds(30))
                }
            }
        }
    }

    private func cancelDrain() {
        drainTask?.cancel()
        drainTask = nil
    }

    /// Advance from `count` characters in to the end of the next
    /// whitespace-delimited chunk, returning the new character count.
    /// Consumes a trailing whitespace run so successive reveals don't
    /// briefly show a word missing its trailing space.
    private static func nextWordBoundary(in text: String, afterCount count: Int) -> Int {
        guard count < text.count else { return text.count }

        let start = text.index(text.startIndex, offsetBy: count)
        var i = start
        // Skip leading whitespace.
        while i < text.endIndex, text[i].isWhitespace {
            i = text.index(after: i)
        }
        // Consume the word.
        while i < text.endIndex, !text[i].isWhitespace {
            i = text.index(after: i)
        }
        // Consume trailing whitespace so the visible cursor lands on
        // the start of the next word, not on a dangling space.
        while i < text.endIndex, text[i].isWhitespace {
            i = text.index(after: i)
        }
        let newCount = text.distance(from: text.startIndex, to: i)
        // Guarantee progress even on degenerate input (all whitespace).
        return max(newCount, count + 1)
    }
}
