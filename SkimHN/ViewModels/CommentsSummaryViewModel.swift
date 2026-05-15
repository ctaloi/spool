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
    @Published private(set) var text: String = ""

    private var task: Task<Void, Never>?
    /// Throttles streamed updates — see `SummaryViewModel` for the
    /// rationale. Same 80ms cadence so both summary cards feel
    /// consistent.
    private var streamingBuffer: String?
    private var flushScheduled: Bool = false
    private let flushInterval: Duration = .milliseconds(80)

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

        streamingBuffer = nil
        state = .streaming
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = SummaryService.shared.summarizeComments(
                    title: title,
                    comments: transcript
                )
                for try await partial in stream {
                    if Task.isCancelled { return }
                    self.streamingBuffer = partial
                    self.scheduleFlush()
                }
                if !Task.isCancelled, let final = self.streamingBuffer {
                    self.text = final
                    self.streamingBuffer = nil
                }
                if !Task.isCancelled {
                    self.state = .done
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
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        streamingBuffer = nil
        flushScheduled = false
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.flushInterval ?? .milliseconds(80))
            guard let self else { return }
            self.flushScheduled = false
            if let buffer = self.streamingBuffer {
                self.text = buffer
            }
        }
    }
}
