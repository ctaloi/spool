import Foundation
import Combine

/// Lightweight cross-view router for handling deep links from
/// Spotlight, widgets, and notifications. Views observe and react to
/// `pendingStoryID` / `pendingFeedSource` to navigate.
///
/// Each pending field is one-shot — `consume*` returns and clears.
/// That way SwiftUI's value-watcher pattern (`.onChange(of: …)`)
/// fires once per route request, without firing again on re-render.
@MainActor
final class AppRouter: ObservableObject {
    @Published private(set) var pendingStoryID: Int?
    @Published private(set) var pendingFeedSource: String?
    /// DEBUG-only — name of a modal sheet to auto-present at launch
    /// ("settings", "login", "submit", "nowplaying"). Driven by the
    /// `-SpoolShowSheet` launch arg in the screenshot harness; left
    /// here on AppRouter rather than scattered as private state so
    /// any view that owns the matching sheet binding can observe it.
    #if DEBUG
    @Published var pendingSheet: String?
    #endif

    /// Parse a `spool://...` URL and set the matching pending state.
    /// Supported forms today:
    ///   - `spool://story/<id>`       — open the detail page.
    ///   - `spool://feed/<keyword>`   — switch the main list (top,
    ///                                   new, trending, saved, etc.).
    func handle(_ url: URL) {
        guard url.scheme == "spool" else { return }
        guard let host = url.host else { return }

        let path = url.pathComponents
            .filter { $0 != "/" }

        switch host {
        case "story":
            if let first = path.first, let id = Int(first) {
                pendingStoryID = id
            }
        case "feed":
            if let first = path.first {
                pendingFeedSource = first
            }
        default:
            break
        }
    }

    /// Pull and clear the pending story ID. Called by the view once
    /// it has navigated. Subsequent reads return nil until the next
    /// deep link.
    func consumeStoryID() -> Int? {
        let value = pendingStoryID
        pendingStoryID = nil
        return value
    }

    func consumeFeedSource() -> String? {
        let value = pendingFeedSource
        pendingFeedSource = nil
        return value
    }
}
