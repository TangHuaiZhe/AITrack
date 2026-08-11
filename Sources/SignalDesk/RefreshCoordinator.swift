import Foundation

protocol SignalFetching {
    func fetchX(_ sources: [TrackedSource]) async throws -> [UUID: [SignalEvent]]
    func fetch(_ source: TrackedSource) async throws -> [SignalEvent]
}

extension FeedClient: SignalFetching {}

struct RefreshResult {
    let addedEvents: [SignalEvent]
    let checkedAtBySourceID: [UUID: Date]
    let failures: [String]
    let refreshedAt: Date
}

struct RefreshCoordinator {
    private let client: any SignalFetching
    private let now: () -> Date

    init(client: any SignalFetching = FeedClient(), now: @escaping () -> Date = { Date() }) {
        self.client = client
        self.now = now
    }

    func refresh(
        sources: [TrackedSource],
        existingEvents: [SignalEvent],
        provider: XProvider
    ) async -> RefreshResult {
        let refreshedAt = now()
        let enabledSources = sources.filter(\.isEnabled)
        let brightDataXSources = provider == .brightData
            ? enabledSources.filter { $0.sourceKind == .x }
            : []
        var knownEventIDs = Set(existingEvents.map(\.id))
        var addedEvents: [SignalEvent] = []
        var checkedAtBySourceID: [UUID: Date] = [:]
        var failures: [String] = []

        if !brightDataXSources.isEmpty {
            do {
                let incomingBySource = try await client.fetchX(brightDataXSources)
                for source in brightDataXSources {
                    appendNew(
                        incomingBySource[source.id] ?? [],
                        to: &addedEvents,
                        knownEventIDs: &knownEventIDs
                    )
                    checkedAtBySourceID[source.id] = refreshedAt
                }
            } catch {
                failures.append(contentsOf: brightDataXSources.map {
                    "\($0.name)：\(error.localizedDescription)"
                })
            }
        }

        for source in enabledSources where !(provider == .brightData && source.sourceKind == .x) {
            if source.sourceKind == .mediaSearch,
               let lastCheckedAt = source.lastCheckedAt,
               refreshedAt.timeIntervalSince(lastCheckedAt) < 6 * 60 * 60 {
                continue
            }
            do {
                let incoming = try await client.fetch(source)
                appendNew(incoming, to: &addedEvents, knownEventIDs: &knownEventIDs)
                checkedAtBySourceID[source.id] = refreshedAt
            } catch {
                failures.append("\(source.name)：\(error.localizedDescription)")
            }
        }

        return RefreshResult(
            addedEvents: addedEvents,
            checkedAtBySourceID: checkedAtBySourceID,
            failures: failures,
            refreshedAt: refreshedAt
        )
    }

    private func appendNew(
        _ incoming: [SignalEvent],
        to addedEvents: inout [SignalEvent],
        knownEventIDs: inout Set<String>
    ) {
        for event in incoming where knownEventIDs.insert(event.id).inserted {
            addedEvents.append(event)
        }
    }
}
