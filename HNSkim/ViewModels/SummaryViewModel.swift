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
    @Published private(set) var text: String = ""

    private var task: Task<Void, Never>?

    var availability: SummaryAvailability { SummaryService.shared.availability }

    var canSummarize: Bool {
        if case .available = availability { return true }
        return false
    }

    func summarize(title: String, url: URL) {
        cancel()
        text = ""
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
                    self.state = .streaming
                    let stream = SummaryService.shared.summarize(
                        title: title,
                        articleText: article
                    )
                    for try await partial in stream {
                        if Task.isCancelled { return }
                        self.text = partial
                    }
                    if !Task.isCancelled {
                        self.state = .done
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
                    return
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
