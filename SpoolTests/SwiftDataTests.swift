import Testing
import Foundation
import SwiftData
@testable import Spool

/// Smoke-level SwiftData tests using an in-memory ModelContainer.
/// These cover the Spool/Archive predicate boundary — the same
/// boundary that drives which rows appear in the sidebar badges
/// and the main list. If a future schema change broke this, the
/// app would look fine but the archive would silently include
/// active items or vice versa.
@MainActor
struct SwiftDataTests {

    /// Build an in-memory container so each test is hermetic.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            SpooledStory.self,
            SavedStory.self,
            ReadStory.self,
            FollowedUser.self,
            ScoreSnapshot.self,
            SeenMention.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    private func makeStory(
        id: Int = 1,
        archived: Date? = nil,
        position: Int = 0
    ) -> SpooledStory {
        SpooledStory(
            id: id,
            title: "Story \(id)",
            urlString: nil,
            author: "tester",
            score: 10,
            descendants: 0,
            position: position,
            archivedAt: archived
        )
    }

    @Test func archivedFilterExcludesArchivedItems() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(makeStory(id: 1, archived: nil))
        context.insert(makeStory(id: 2, archived: .now))
        try context.save()

        let descriptor = FetchDescriptor<SpooledStory>(
            predicate: #Predicate { $0.archivedAt == nil }
        )
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results.first?.id == 1)
    }

    @Test func archivedFilterIncludesOnlyArchivedItems() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(makeStory(id: 1, archived: nil))
        context.insert(makeStory(id: 2, archived: .now))
        context.insert(makeStory(id: 3, archived: .now))
        try context.save()

        let descriptor = FetchDescriptor<SpooledStory>(
            predicate: #Predicate { $0.archivedAt != nil }
        )
        let results = try context.fetch(descriptor)
        #expect(results.count == 2)
        #expect(Set(results.map(\.id)) == [2, 3])
    }

    @Test func archiveTransitionsItemFromSpoolToArchive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let story = makeStory(id: 1, archived: nil)
        context.insert(story)
        try context.save()

        let spoolBefore = try context.fetch(
            FetchDescriptor<SpooledStory>(predicate: #Predicate { $0.archivedAt == nil })
        )
        #expect(spoolBefore.count == 1)

        // Archive it.
        story.archivedAt = .now
        try context.save()

        let spoolAfter = try context.fetch(
            FetchDescriptor<SpooledStory>(predicate: #Predicate { $0.archivedAt == nil })
        )
        let archiveAfter = try context.fetch(
            FetchDescriptor<SpooledStory>(predicate: #Predicate { $0.archivedAt != nil })
        )
        #expect(spoolAfter.isEmpty)
        #expect(archiveAfter.count == 1)
    }

    @Test func restoreFromArchiveMovesItemBackToSpool() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let story = makeStory(id: 1, archived: .now)
        context.insert(story)
        try context.save()

        // Restore.
        story.archivedAt = nil
        try context.save()

        let spool = try context.fetch(
            FetchDescriptor<SpooledStory>(predicate: #Predicate { $0.archivedAt == nil })
        )
        let archive = try context.fetch(
            FetchDescriptor<SpooledStory>(predicate: #Predicate { $0.archivedAt != nil })
        )
        #expect(spool.count == 1)
        #expect(archive.isEmpty)
    }

    @Test func spoolSortByPosition() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(makeStory(id: 1, position: 30))
        context.insert(makeStory(id: 2, position: 10))
        context.insert(makeStory(id: 3, position: 20))
        try context.save()

        let descriptor = FetchDescriptor<SpooledStory>(
            predicate: #Predicate { $0.archivedAt == nil },
            sortBy: [SortDescriptor(\.position, order: .forward)]
        )
        let results = try context.fetch(descriptor)
        #expect(results.map(\.id) == [2, 3, 1])
    }

    @Test func deletingItemRemovesFromBothQueries() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let active = makeStory(id: 1, archived: nil)
        let archived = makeStory(id: 2, archived: .now)
        context.insert(active)
        context.insert(archived)
        try context.save()

        context.delete(active)
        context.delete(archived)
        try context.save()

        let all = try context.fetch(FetchDescriptor<SpooledStory>())
        #expect(all.isEmpty)
    }
}
