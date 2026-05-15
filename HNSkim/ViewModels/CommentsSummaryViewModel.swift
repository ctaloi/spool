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
                    self.text = partial
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
    }
}
