import Foundation
import Testing
@testable import SignalDesk

struct RefreshCoordinatorTests {
    @Test
    func batchesBrightDataXAndSkipsRecentlyCheckedMediaSources() async {
        let xSource = TrackedSource(
            name: "Example X",
            role: "X",
            topics: [],
            sourceKind: .x,
            feedURL: "example"
        )
        let mediaSource = TrackedSource(
            name: "Example Media",
            role: "Media",
            topics: [],
            sourceKind: .mediaSearch,
            feedURL: "https://example.com/media",
            lastCheckedAt: Date(timeIntervalSince1970: 9_000)
        )
        let now = Date(timeIntervalSince1970: 10_000)
        let xEvent = testEvent(id: "x", source: xSource)
        let fetcher = StubSignalFetcher(
            xEvents: [xSource.id: [xEvent]],
            singleEvents: [mediaSource.id: [testEvent(id: "media", source: mediaSource)]]
        )

        let result = await RefreshCoordinator(client: fetcher, now: { now }).refresh(
            sources: [xSource, mediaSource],
            existingEvents: [],
            provider: .brightData
        )

        #expect(fetcher.fetchXCallCount == 1)
        #expect(fetcher.fetchedSourceIDs == [])
        #expect(result.addedEvents.map(\.id) == ["x"])
        #expect(result.checkedAtBySourceID[xSource.id] == now)
    }

    @Test
    func deduplicatesIncomingEventsAcrossSourcesAndPreservesFailureMessages() async {
        let first = TrackedSource(
            name: "First",
            role: "RSS",
            topics: [],
            sourceKind: .rss,
            feedURL: "https://example.com/first"
        )
        let second = TrackedSource(
            name: "Second",
            role: "RSS",
            topics: [],
            sourceKind: .rss,
            feedURL: "https://example.com/second"
        )
        let duplicate = testEvent(id: "same", source: first)
        let fetcher = StubSignalFetcher(
            singleEvents: [first.id: [duplicate], second.id: [duplicate]],
            failingSourceIDs: [second.id]
        )

        let result = await RefreshCoordinator(client: fetcher, now: Date.init).refresh(
            sources: [first, second],
            existingEvents: [],
            provider: .twitterAPIIO
        )

        #expect(result.addedEvents.map(\.id) == ["same"])
        #expect(result.failures.count == 1)
        #expect(result.failures[0].hasPrefix("Second："))
    }

    private func testEvent(id: String, source: TrackedSource) -> SignalEvent {
        SignalEvent(
            id: id,
            sourceID: source.id,
            sourceKind: source.sourceKind,
            sourceName: source.name,
            title: id,
            summary: "",
            url: nil,
            publishedAt: Date(timeIntervalSince1970: 1),
            category: .activity,
            importance: 50,
            matchedTopics: []
        )
    }
}

private final class StubSignalFetcher: SignalFetching, @unchecked Sendable {
    let xEvents: [UUID: [SignalEvent]]
    let singleEvents: [UUID: [SignalEvent]]
    let failingSourceIDs: Set<UUID>
    private(set) var fetchXCallCount = 0
    private(set) var fetchedSourceIDs: [UUID] = []

    init(
        xEvents: [UUID: [SignalEvent]] = [:],
        singleEvents: [UUID: [SignalEvent]] = [:],
        failingSourceIDs: Set<UUID> = []
    ) {
        self.xEvents = xEvents
        self.singleEvents = singleEvents
        self.failingSourceIDs = failingSourceIDs
    }

    func fetchX(_ sources: [TrackedSource]) async throws -> [UUID: [SignalEvent]] {
        fetchXCallCount += 1
        return xEvents
    }

    func fetch(_ source: TrackedSource) async throws -> [SignalEvent] {
        fetchedSourceIDs.append(source.id)
        if failingSourceIDs.contains(source.id) {
            throw StubError.failed
        }
        return singleEvents[source.id] ?? []
    }

    enum StubError: LocalizedError {
        case failed

        var errorDescription: String? { "stub failure" }
    }
}
