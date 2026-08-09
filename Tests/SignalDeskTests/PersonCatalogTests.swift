import Foundation
import Testing
@testable import SignalDesk

struct PersonCatalogTests {
    @Test func containsAllRequestedPeopleAndUniqueSources() {
        let people = PersonPreset.aiRoboticsLeaders
        let sources = people.flatMap { $0.trackedSources() }
        let sourceKeys = Set(sources.map { "\($0.sourceKind.rawValue)|\($0.feedURL.lowercased())" })

        #expect(people.count == 12)
        #expect(sources.count == 19)
        #expect(sourceKeys.count == sources.count)
        #expect(people.contains { $0.id == "elon-musk" })
        #expect(people.contains { $0.id == "wang-xingxing" })
        #expect(people.contains { $0.id == "satya-nadella" })
        #expect(people.contains { $0.id == "ray-dalio" })
        #expect(sources.contains { $0.name == "李飞飞 / Fei-Fei Li · a16z 播客与访谈" })
    }

    @Test func usesMediaSearchAndPublicFeedsWithoutX() {
        let sources = PersonPreset.aiRoboticsLeaders.flatMap { $0.trackedSources() }

        #expect(sources.filter { $0.sourceKind == .x }.isEmpty)
        #expect(sources.filter { $0.sourceKind == .mediaSearch }.count == 12)
        #expect(sources.filter { $0.sourceKind == .rss }.allSatisfy { $0.isEnabled })
    }

    @Test func tracksRayDalioLongFormAndOfficialVideo() throws {
        let rayDalio = try #require(
            PersonPreset.aiRoboticsLeaders.first { $0.id == "ray-dalio" }
        )
        let sources = rayDalio.trackedSources()

        #expect(rayDalio.defaultDomains == [.investmentBusiness])
        #expect(sources.count == 2)
        #expect(sources.contains { $0.sourceKind == .mediaSearch })
        #expect(sources.contains {
            $0.feedURL == "https://www.youtube.com/feeds/videos.xml?channel_id=UCqvaXJ1K3HheTPNjH-KpwXQ"
        })
    }

    @Test func tracksFeiFeiLiA16ZPodcastFeed() throws {
        let feiFeiLi = try #require(
            PersonPreset.aiRoboticsLeaders.first { $0.id == "fei-fei-li" }
        )
        let source = try #require(
            feiFeiLi.trackedSources().first { $0.name.contains("a16z") }
        )

        #expect(source.sourceKind == .rss)
        #expect(source.feedURL.contains("a16z.com%2Fpodcast") || source.feedURL.contains("a16z.com/podcast"))
        #expect(source.isEnabled)
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
