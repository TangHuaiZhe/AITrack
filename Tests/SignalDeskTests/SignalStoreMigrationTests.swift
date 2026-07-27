import Foundation
import Testing
@testable import SignalDesk

struct SignalStoreMigrationTests {
    @Test @MainActor
    func installsRequestedPeopleOnlyOnce() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let stateURL = directory.appending(path: "state.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = SignalStore(stateURL: stateURL)
        let firstKeys = Set(first.sources.map { "\($0.sourceKind.rawValue)|\($0.feedURL.lowercased())" })
        let second = SignalStore(stateURL: stateURL)

        #expect(first.sources.count == 17)
        #expect(firstKeys.count == first.sources.count)
        #expect(first.sources.filter { $0.sourceKind == .x }.isEmpty)
        #expect(first.sources.filter { $0.sourceKind == .mediaSearch }.count == 11)
        #expect(second.sources.count == first.sources.count)
    }

    @Test @MainActor
    func markReadUpdatesAndPersistsEvent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let stateURL = directory.appending(path: "state.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SignalStore(stateURL: stateURL)
        let eventID = try #require(store.events.first?.id)
        #expect(store.events.first { $0.id == eventID }?.isRead == false)

        store.markRead(eventID)

        #expect(store.events.first { $0.id == eventID }?.isRead == true)
        let reloaded = SignalStore(stateURL: stateURL)
        #expect(reloaded.events.first { $0.id == eventID }?.isRead == true)
    }

    @Test @MainActor
    func migratesLegacyEventsToCanonicalDomains() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let stateURL = directory.appending(path: "state.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let source = TrackedSource(
            name: "Legacy feed",
            role: "Test",
            topics: ["robot", "GPU"],
            sourceKind: .rss,
            feedURL: "https://example.com/feed.xml"
        )
        let event = SignalEvent(
            id: "legacy-domain-event",
            sourceID: source.id,
            sourceName: source.name,
            title: "Humanoid robot inference moves to a new GPU",
            summary: "A physical AI system runs on an edge accelerator.",
            url: nil,
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000),
            category: .viewpoint,
            importance: 80,
            matchedTopics: ["robot", "GPU"]
        )
        let snapshot = AppSnapshot(
            sources: [source],
            events: [event],
            lastRefreshAt: nil,
            installedCatalogIDs: ["ai-robotics-longform-v4"]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: stateURL)

        let migrated = SignalStore(stateURL: stateURL)
        let domains = try #require(migrated.events.first?.domains)

        #expect(domains.contains(.robotics))
        #expect(domains.contains(.compute))
    }
}
