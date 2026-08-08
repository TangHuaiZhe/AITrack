import Foundation
import Testing
@testable import SignalDesk

struct CuratedSourceCatalogTests {
    @Test func containsAllRequestedResearchSources() {
        let sources = CuratedSourcePreset.researchSources.map { $0.trackedSource() }
        let keys = Set(sources.map { "\($0.sourceKind.rawValue)|\($0.feedURL)" })

        #expect(sources.count == 9)
        #expect(keys.count == 9)
        #expect(sources.allSatisfy { $0.sourceKind == .rss })
        #expect(sources.contains { $0.name.contains("Howard Marks") })
        #expect(sources.contains { $0.name.contains("AI + a16z") })
    }

    @Test func usesWorkingRSSAndPodcastEndpoints() {
        let feedURLs = Set(CuratedSourcePreset.researchSources.map(\.feedURL))

        #expect(feedURLs.contains("https://aswathdamodaran.blogspot.com/feeds/posts/default?alt=rss"))
        #expect(feedURLs.contains("https://www.bloomberg.com/opinion/authors/ARbTQlRLRjE/matthew-s-levine.rss"))
        #expect(feedURLs.contains("https://feeds.simplecast.com/JGE3yC0V"))
        #expect(feedURLs.contains("https://feeds.simplecast.com/Hb_IuXOo"))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TRACKAI_LIVE_CURATED_TEST"] == "1"))
    func fetchesLiveCuratedFeeds() async {
        var failures: [String] = []
        await withTaskGroup(of: (String, String?).self) { group in
            for preset in CuratedSourcePreset.researchSources {
                group.addTask {
                    do {
                        let events = try await FeedClient().fetch(preset.trackedSource())
                        return (preset.name, events.isEmpty ? "返回 0 条" : nil)
                    } catch {
                        return (preset.name, error.localizedDescription)
                    }
                }
            }
            for await (name, failure) in group where failure != nil {
                failures.append("\(name)：\(failure!)")
            }
        }
        #expect(failures.isEmpty, "真实来源失败：\(failures.joined(separator: "；"))")
    }
}
