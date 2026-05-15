import Foundation

/// Computes a "what you missed since you last opened" catch-up using
/// Foundation Models against the current Top feed's headlines.
@MainActor
final class DigestViewModel: ObservableObject {
    enum State {
        case idle
        case streaming
        case done
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var text: String = ""

    private var task: Task<Void, Never>?

    var availability: SummaryAvailability { SummaryService.shared.availability }

    var canRun: Bool {
        if case .available = availability { return true }
        return false
    }

    /// Generate a digest of the supplied story titles. Caller is
    /// expected to pick the right set (e.g., recent top stories the
    /// user hasn't seen yet).
    func generate(stories: [HNItem]) {
        cancel()
        let headlines = stories
            .prefix(15)
            .compactMap { story -> String? in
                guard let title = story.title else { return nil }
                if let host = story.host {
                    return "- \(title) (\(host))"
                }
                return "- \(title)"
            }
            .joined(separator: "\n")
        guard !headlines.isEmpty else { return }

        text = ""
        state = .streaming
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = SummaryService.shared.digestRecentStories(headlines: headlines)
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
                self.state = .error(SummaryError.classify(error).localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
