import Foundation
import Testing
@testable import SignalDesk

struct AppPersistenceTests {
    @Test
    func decodesSnapshotsWrittenBeforeSchemaVersion() throws {
        let source = TrackedSource.starterSources[0]
        let legacyJSON = """
        {
          "events": [],
          "sources": [
            {
              "feedURL": "\(source.feedURL)",
              "id": "\(source.id.uuidString)",
              "isEnabled": true,
              "name": "\(source.name)",
              "role": "\(source.role)",
              "sourceKind": "rss",
              "topics": []
            }
          ]
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder.signalDesk.decode(AppSnapshot.self, from: legacyJSON)

        #expect(snapshot.schemaVersion == AppSnapshot.currentSchemaVersion)
        #expect(snapshot.sources.count == 1)
        #expect(snapshot.events.isEmpty)
    }

    @Test
    func persistenceRoundTripsSchemaVersionAndState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "signaldesk-persistence-(UUID().uuidString)")
        let url = directory.appending(path: "state.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = TrackedSource.starterSources[0]
        let snapshot = AppSnapshot(
            sources: [source],
            events: [],
            lastRefreshAt: nil,
            installedCatalogIDs: []
        )
        let persistence = SignalStatePersistence(url: url)

        try persistence.save(snapshot)
        let restored = try persistence.load()

        #expect(restored.schemaVersion == AppSnapshot.currentSchemaVersion)
        #expect(restored.sources == [source])
    }
}
