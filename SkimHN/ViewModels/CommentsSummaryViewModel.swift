import Foundation

@MainActor
final class CommentsSummaryViewModel: ObservableObject {
    enum FailureKind {
        case guardrail
        case contextOverflow
        case other
    }

    enum State {
        case idle
        case streaming
        case done
        case error(message: String, kind: FailureKind)
    }

    @Published private(set) var state: State = .idle
    /// See `SummaryViewModel.text` — display surface for the
    /// word-by-word drain.
    @Published private(set) var text: String = ""

    private var task: Task<Void, Never>?
    private var drainTask: Task<Void, Never>?
    private var fullText: String = ""
    private var streamFinished: Bool = false

    private let baseWordInterval: Duration = .milliseconds(40)
    private let fastWordInterval: Duration = .milliseconds(15)
    private let fastDrainBacklog: Int = 150

    var availability: SummaryAvailability { SummaryService.shared.availability }

    var canSummarize: Bool {
        if case .available = availability { return true }
        return false
    }

    func summarize(title: String, transcript: String) {
        cancel()
        text = ""

        guard !transcript.isEmpty else {
            state = .error(message: "No comments to summarize yet.", kind: .other)
            return
        }

        fullText = ""
        streamFinished = false
        state = .streaming
        startDrain()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = SummaryService.shared.summarizeComments(
                    title: title,
                    comments: transcript
                )
                for try await partial in stream {
                    if Task.isCancelled { return }
                    self.fullText = partial
                }
                if !Task.isCancelled {
                    self.streamFinished = true
                }
            } catch is CancellationError {
                // ignore
            } catch {
                let classified = SummaryError.classify(error)
                let kind: FailureKind
                switch classified {
                case .guardrail: kind = .guardrail
                case .contextTooLong: kind = .contextOverflow
                default: kind = .other
                }
                self.state = .error(
                    message: classified.localizedDescription,
                    kind: kind
                )
                self.cancelDrain()
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
                    self.state = .done
                    return
                } else {
                    try? await Task.sleep(for: .milliseconds(30))
                }
            }
        }
    }

    private func cancelDrain() {
        drainTask?.cancel()
        drainTask = nil
    }

    private static func nextWordBoundary(in text: String, afterCount count: Int) -> Int {
        guard count < text.count else { return text.count }

        let start = text.index(text.startIndex, offsetBy: count)
        var i = start
        while i < text.endIndex, text[i].isWhitespace {
            i = text.index(after: i)
        }
        while i < text.endIndex, !text[i].isWhitespace {
            i = text.index(after: i)
        }
        while i < text.endIndex, text[i].isWhitespace {
            i = text.index(after: i)
        }
        let newCount = text.distance(from: text.startIndex, to: i)
        return max(newCount, count + 1)
    }
}
