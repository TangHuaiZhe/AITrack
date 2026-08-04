import Foundation
import Testing
@testable import SignalDesk

struct DailyBriefTests {
    @Test
    func promptRequiresCompanyImpactAndValuationReview() {
        let event = SignalEvent(
            id: "brief-event",
            sourceID: UUID(),
            sourceName: "AI Founder",
            title: "A new inference model launch",
            summary: "The model reduces inference cost.",
            url: "https://example.com/event",
            publishedAt: Date(timeIntervalSince1970: 1_754_000_000),
            category: .viewpoint,
            importance: 88,
            matchedTopics: ["AI"],
            aiSummary: nil
        )
        let news = DailyNewsItem(
            id: "news-1",
            topic: .chips,
            title: "New accelerator supply agreement",
            summary: "A supplier announced a new capacity agreement.",
            url: "https://example.com/news",
            publishedAt: Date(timeIntervalSince1970: 1_754_000_100)
        )
        let prompt = DailyBriefService.prompt(
            events: [event],
            news: [news],
            windowStart: Date(timeIntervalSince1970: 1_753_913_600),
            windowEnd: Date(timeIntervalSince1970: 1_754_000_000)
        )

        #expect(prompt.contains("# 影响力最大的全网新闻"))
        #expect(prompt.contains("影响公司"))
        #expect(prompt.contains("受益/受损产品"))
        #expect(prompt.contains("估值审查"))
        #expect(prompt.contains("估值数据不足"))
        #expect(prompt.contains("New accelerator supply agreement"))
        #expect(prompt.contains("A new inference model launch"))
    }

    @Test
    func dailyBriefRoundTripsThroughCodable() throws {
        let brief = DailyBrief(
            id: "2026-08-04",
            generatedAt: Date(timeIntervalSince1970: 1_754_000_000),
            windowStart: Date(timeIntervalSince1970: 1_753_913_600),
            windowEnd: Date(timeIntervalSince1970: 1_754_000_000),
            trackedEventCount: 12,
            newsItemCount: 24,
            provider: .ollama,
            content: "# 今日结论\n内容"
        )
        let decoded = try JSONDecoder().decode(
            DailyBrief.self,
            from: JSONEncoder().encode(brief)
        )

        #expect(decoded == brief)
    }
}
