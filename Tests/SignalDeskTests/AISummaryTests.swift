import Foundation
import Testing
@testable import SignalDesk

struct AISummaryTests {
    @Test
    func extractsArticleAndRemovesPageChrome() {
        let html = """
        <html>
          <body>
            <nav>Navigation noise</nav>
            <article>
              <h1>AI infrastructure</h1>
              <p>Demand will continue growing &amp; move toward edge devices.</p>
              <script>doNotInclude()</script>
              <p>Expected capacity: &#49;&#48;&#48; units.</p>
            </article>
            <footer>Footer noise</footer>
          </body>
        </html>
        """

        let text = ArticleContentFetcher.extractReadableText(from: html)

        #expect(text.contains("AI infrastructure"))
        #expect(text.contains("Demand will continue growing & move toward edge devices."))
        #expect(text.contains("Expected capacity: 100 units."))
        #expect(!text.contains("doNotInclude"))
        #expect(!text.contains("Navigation noise"))
    }

    @Test
    func summaryPersistsWithEvent() throws {
        let summary = AISummary(
            content: "一句话结论：本地总结可用",
            provider: .ollama,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let event = SignalEvent(
            id: "summary-test",
            sourceID: UUID(),
            sourceName: "Test",
            title: "Interview",
            summary: "Description",
            url: "https://example.com",
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000),
            category: .viewpoint,
            importance: 80,
            matchedTopics: ["AI"],
            aiSummary: summary
        )

        let decoded = try JSONDecoder().decode(
            SignalEvent.self,
            from: JSONEncoder().encode(event)
        )

        #expect(decoded.aiSummary == summary)
    }
}
