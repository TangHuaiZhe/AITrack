import Foundation
import Testing
@testable import SignalDesk

struct PersonCatalogTests {
    @Test func containsAllRequestedPeopleAndUniqueSources() {
        let people = PersonPreset.aiRoboticsLeaders
        let sources = people.flatMap { $0.trackedSources() }
        let sourceKeys = Set(sources.map { "\($0.sourceKind.rawValue)|\($0.feedURL.lowercased())" })

        #expect(people.count == 11)
        #expect(sources.count == 16)
        #expect(sourceKeys.count == sources.count)
        #expect(people.contains { $0.id == "elon-musk" })
        #expect(people.contains { $0.id == "wang-xingxing" })
        #expect(people.contains { $0.id == "satya-nadella" })
    }

    @Test func usesMediaSearchAndPublicFeedsWithoutX() {
        let sources = PersonPreset.aiRoboticsLeaders.flatMap { $0.trackedSources() }

        #expect(sources.filter { $0.sourceKind == .x }.isEmpty)
        #expect(sources.filter { $0.sourceKind == .mediaSearch }.count == 11)
        #expect(sources.filter { $0.sourceKind == .rss }.allSatisfy { $0.isEnabled })
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TRACKAI_LIVE_MEDIA_TEST"] == "1"))
    func everyMediaSearchReturnsResults() async throws {
        var peopleWithResults = 0
        for person in PersonPreset.aiRoboticsLeaders {
            let source = try #require(person.trackedSources().first { $0.sourceKind == .mediaSearch })
            let events = try await FeedClient().fetch(source)
            if !events.isEmpty { peopleWithResults += 1 }
            #expect(events.allSatisfy { $0.category == .viewpoint })
            #expect(events.allSatisfy { MediaClassifier.isLongForm(title: $0.title) })
            #expect(events.allSatisfy {
                MediaClassifier.matchesPerson(
                    title: $0.title,
                    aliases: source.requiredTitleTerms ?? []
                )
            })
        }
        #expect(peopleWithResults >= 6)
    }
}
