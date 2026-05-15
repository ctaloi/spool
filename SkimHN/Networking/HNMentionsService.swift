import Foundation

/// One reply to one of the user's comments — the unit rendered in the
/// Mentions feed. Carries both sides of the exchange plus enough
/// context to open the parent story.
struct MentionRecord: Identifiable, Sendable, Hashable {
    let reply: HNItem
    let parentComment: AuthoredComment
    var id: Int { reply.id }
}

/// Walks Algolia for the signed-in user's recent comments, then
/// Firebase for each comment's current kids, and returns the kid
/// items as MentionRecords. No persistence and no "is it unread"
/// logic — those concerns belong to the view model + SeenMention.
actor HNMentionsService {
    static let shared = HNMentionsService()

    /// Cap on how many of the user's recent comments we walk per
    /// refresh. HN users with very long histories would otherwise
    /// trigger hundreds of Firebase fetches per refresh.
    private let parentCap = 20

    func fetchMentions(for username: String) async throws -> [MentionRecord] {
        let myComments = try await HNSearchService.shared
            .searchCommentsByAuthor(username, hitsPerPage: parentCap)
        guard !myComments.isEmpty else { return [] }

        // Refresh each of my comments via Firebase to get current
        // kids — Algolia's index lags Firebase by minutes.
        let freshParents: [HNItem] = await withTaskGroup(
            of: HNItem?.self
        ) { group in
            for myComment in myComments {
                group.addTask {
                    try? await HNAPI.shared.item(id: myComment.id)
                }
            }
            var buffer: [HNItem] = []
            for await item in group {
                if let item { buffer.append(item) }
            }
            return buffer
        }

        // Pair each fresh parent with its AuthoredComment so we can
        // surface story_title without an extra fetch up to the root.
        let parentByID = Dictionary(
            uniqueKeysWithValues: myComments.map { ($0.id, $0) }
        )
        var pairedKids: [(parent: AuthoredComment, kidID: Int)] = []
        for parent in freshParents {
            guard let context = parentByID[parent.id] else { continue }
            for kidID in parent.kids ?? [] {
                pairedKids.append((context, kidID))
            }
        }

        // Fetch every reply in parallel. Drop dead / deleted ones —
        // we never want them showing up as "mentions".
        let replies: [MentionRecord] = await withTaskGroup(
            of: MentionRecord?.self
        ) { group in
            for pairing in pairedKids {
                group.addTask {
                    guard let kid = try? await HNAPI.shared.item(id: pairing.kidID),
                          kid.deleted != true,
                          kid.dead != true
                    else { return nil }
                    return MentionRecord(reply: kid, parentComment: pairing.parent)
                }
            }
            var buffer: [MentionRecord] = []
            for await record in group {
                if let record { buffer.append(record) }
            }
            return buffer
        }

        return replies.sorted { ($0.reply.time ?? 0) > ($1.reply.time ?? 0) }
    }
}
