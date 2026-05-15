import Foundation

/// Drives the "ask a question about this thread" feature. Same
/// drain-based streaming used by SummaryViewModel — model fills a
/// `fullText` buffer, a separate ticker pulls words into `text` at a
/// readable cadence so the answer doesn't appear in jerky bursts.
@MainActor
final class ThreadQuestionViewModel: ObservableObject {
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
    @Published private(set) var text: String = ""
    @Published var question: String = ""

    private var task: Task<Void, Never>?
    private var fullText: String = ""
    private var drainTask: Task<Void, Never>?

    var availability: SummaryAvailability { SummaryService.shared.availability }

    var canAnswer: Bool {
        if case .available = availability { return true }
        return false
    }

    /// Ask a question. Cancels any in-flight question so the user can
    /// re-ask quickly.
    func ask(title: String, transcript: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        cancel()
        text = ""
        fullText = ""
        state = .streaming
        startDrain()

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = SummaryService.shared.answerThreadQuestion(
                    title: title,
                    comments: transcript,
                    question: trimmed
                )
                for try await partial in stream {
                    if Task.isCancelled { return }
                    self.fullText = partial
                }
                if !Task.isCancelled {
                    await self.waitForDrainToCatchUp()
                    self.state = .done
                }
            } catch is CancellationError {
                // ignored
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
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        drainTask?.cancel()
        drainTask = nil
        fullText = ""
    }

    /// Pull words one boundary at a time from `fullText` into `text`
    /// at ~25 wps, accelerating to ~67 wps when the buffer gets ahead.
    private func startDrain() {
        drainTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                let revealed = self.text.count
                if revealed < self.fullText.count {
                    let nextBoundary = self.nextWordBoundary(after: revealed)
                    self.text = String(self.fullText.prefix(nextBoundary))
                    let backlog = self.fullText.count - self.text.count
                    let nanos: UInt64 = backlog > 150 ? 15_000_000 : 40_000_000
                    try? await Task.sleep(nanoseconds: nanos)
                } else {
                    try? await Task.sleep(nanoseconds: 30_000_000)
                }
            }
        }
    }

    private func waitForDrainToCatchUp() async {
        for _ in 0..<200 where text.count < fullText.count {
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        if text.count < fullText.count {
            text = fullText
        }
        drainTask?.cancel()
        drainTask = nil
    }

    private func nextWordBoundary(after index: Int) -> Int {
        guard index < fullText.count else { return index }
        let start = fullText.index(fullText.startIndex, offsetBy: index)
        if let boundary = fullText[start...].firstIndex(where: { $0 == " " || $0 == "\n" }) {
            return fullText.distance(from: fullText.startIndex, to: boundary) + 1
        }
        return fullText.count
    }
}
