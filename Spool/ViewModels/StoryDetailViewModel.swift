import Foundation

/// A flattened comment node with a depth value so we can render an
/// arbitrarily deep tree in a flat List with indentation.
struct CommentNode: Identifiable, Hashable {
    let item: HNItem
    let depth: Int
    var id: Int { item.id }
}

@MainActor
final class StoryDetailViewModel: ObservableObject {
    @Published private(set) var story: HNItem

    @Published private(set) var comments: [CommentNode] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var collapsed: Set<Int> = []

    init(story: HNItem) {
        self.story = story
    }

    /// Comments with subtrees of collapsed parents filtered out. The order
    /// of `comments` is depth-first, so we can do this in a single pass.
    var visibleComments: [CommentNode] {
        guard !collapsed.isEmpty else { return comments }
        var visible: [CommentNode] = []
        var skipBelowDepth: Int? = nil
        for node in comments {
            if let cutoff = skipBelowDepth {
                if node.depth > cutoff { continue }
                skipBelowDepth = nil
            }
            visible.append(node)
            if collapsed.contains(node.id) {
                skipBelowDepth = node.depth
            }
        }
        return visible
    }

    /// How many descendants would be hidden if this node were collapsed —
    /// used to render the "+N" indicator on the collapsed header.
    func hiddenReplyCount(for node: CommentNode) -> Int {
        guard let index = comments.firstIndex(of: node) else { return 0 }
        var count = 0
        for i in (index + 1)..<comments.count {
            if comments[i].depth <= node.depth { break }
            count += 1
        }
        return count
    }

    func toggleCollapse(_ node: CommentNode) {
        if collapsed.contains(node.id) {
            collapsed.remove(node.id)
        } else {
            collapsed.insert(node.id)
        }
    }

    /// Flatten comments into a plain-text transcript suitable for the LLM.
    func commentsTranscript(maxCharacters: Int = 12_000) -> String {
        var out = ""
        for node in comments {
            let indent = String(repeating: "  ", count: node.depth)
            let body = (node.item.text ?? "")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&#x27;", with: "'")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&lt;", with: "<")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            out += "\(indent)- \(body)\n"
            if out.count >= maxCharacters {
                return String(out.prefix(maxCharacters))
            }
        }
        return out
    }

    func loadComments(forceReload: Bool = false) async {
        if !forceReload, !comments.isEmpty { return }
        isLoading = true
        errorMessage = nil
        do {
            // Refresh from the Firebase API. Search-sourced items don't
            // carry `kids`, so without this comments would never load.
            let fresh = try await HNAPI.shared.item(id: story.id)
            story = fresh
            let topIDs = fresh.kids ?? []
            guard !topIDs.isEmpty else {
                comments = []
                collapsed.removeAll()
                isLoading = false
                return
            }

            // Phase 1: load + display top-level comments, then dismiss the
            // spinner. The user sees content fast.
            let topItems = try await HNAPI.shared.items(ids: topIDs)
            let topNodes = topItems.compactMap { item -> CommentNode? in
                guard !item.isDeletedOrDead else { return nil }
                return CommentNode(item: item, depth: 0)
            }
            comments = topNodes
            collapsed.removeAll()
            isLoading = false

            // Phase 2: each top-level subtree loads in parallel and is
            // spliced in after its parent as it arrives. Descendants pop
            // in progressively instead of blocking on the whole tree.
            await withTaskGroup(of: Void.self) { group in
                for parent in topNodes {
                    guard let childIDs = parent.item.kids, !childIDs.isEmpty else { continue }
                    group.addTask { [weak self] in
                        guard let self else { return }
                        guard let subtree = try? await self.loadSubtrees(
                            ids: childIDs, depth: 1
                        ) else { return }
                        await self.insertSubtree(subtree, after: parent)
                    }
                }
            }
        } catch {
            // SwiftUI and URLSession both cancel in-flight work during
            // navigation transitions. That's normal; don't show it as an
            // article-level comment loading failure.
            if Self.isCancellation(error) {
                isLoading = false
                return
            }
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func insertSubtree(_ subtree: [CommentNode], after parent: CommentNode) {
        guard !subtree.isEmpty,
              let index = comments.firstIndex(of: parent)
        else { return }
        comments.insert(contentsOf: subtree, at: index + 1)
    }

    /// Load a level of comments in parallel — every sibling subtree races
    /// concurrently instead of the old depth-first sequential walk.
    ///
    /// `nonisolated` matters: without it, this @MainActor class would
    /// pin every recursive task-group continuation to the main thread,
    /// which is exactly what causes the UI lockup on threads with
    /// hundreds of comments. The function touches no actor-isolated
    /// state — it only awaits `HNAPI.shared.items(...)` (its own actor)
    /// and constructs Sendable `CommentNode` value types — so it's safe
    /// to run off-main. The result hops back to the main actor only at
    /// the caller's `insertSubtree` site, which is where the
    /// `@Published` mutation actually needs to happen.
    nonisolated private func loadSubtrees(ids: [Int], depth: Int) async throws -> [CommentNode] {
        guard !ids.isEmpty, depth < 8 else { return [] }
        let items = try await HNAPI.shared.items(ids: ids)

        return try await withThrowingTaskGroup(of: (Int, [CommentNode]).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    guard !item.isDeletedOrDead else { return (index, []) }
                    var subtree: [CommentNode] = [CommentNode(item: item, depth: depth)]
                    if let kids = item.kids, !kids.isEmpty {
                        let children = try await self.loadSubtrees(ids: kids, depth: depth + 1)
                        subtree.append(contentsOf: children)
                    }
                    return (index, subtree)
                }
            }
            var collected: [(Int, [CommentNode])] = []
            for try await result in group {
                collected.append(result)
            }
            return collected.sorted { $0.0 < $1.0 }.flatMap { $0.1 }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        return false
    }
}
