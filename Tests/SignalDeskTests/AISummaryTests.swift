import Foundation
import Testing
@testable import SignalDesk

struct AISummaryTests {
    @Test
    func automaticSummaryUsesImportanceThreshold() {
        #expect(AISummaryService.automaticSummaryImportanceThreshold == 60)
        #expect(59 < AISummaryService.automaticSummaryImportanceThreshold)
        #expect(60 >= AISummaryService.automaticSummaryImportanceThreshold)
    }

    @Test
    func promptsRequireDetailedCoverageOfMaterial() {
        let event = SignalEvent(
            id: "prompt-event",
            sourceID: UUID(),
            sourceName: "Example Founder",
            title: "AI infrastructure interview",
            summary: "A discussion about model efficiency.",
            url: "https://example.com/interview",
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000),
            category: .viewpoint,
            importance: 80,
            matchedTopics: ["AI"],
            aiSummary: nil
        )
        let eventPrompt = AISummaryService.prompt(
            event: event,
            articleText: "The speaker described a five-year roadmap and two risks."
        )

        #expect(eventPrompt.contains("完整情报拆解"))
        #expect(eventPrompt.contains("# 主要观点与论证链"))
        #expect(eventPrompt.contains("# 原文覆盖说明"))
        #expect(eventPrompt.contains("本次送入模型的材料长度"))
        #expect(eventPrompt.contains("The speaker described a five-year roadmap and two risks."))

        let writing = InvestorWriting(
            id: "prompt-writing",
            investorID: "warren-buffett",
            title: "2024 Shareholder Letter",
            author: "Warren Buffett",
            publisher: "Berkshire Hathaway",
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000),
            period: "2024",
            kind: .shareholderLetter,
            attribution: .namedAuthor,
            sourceURL: "https://example.com/letter.pdf",
            sourceNote: "Official shareholder letter"
        )
        let writingPrompt = AISummaryService.writingPrompt(
            writing: writing,
            articleText: "The letter discusses cash, insurance underwriting and capital allocation."
        )

        #expect(writingPrompt.contains("完整的中文投资分析"))
        #expect(writingPrompt.contains("# 公司、行业与宏观判断"))
        #expect(writingPrompt.contains("# 业绩、估值与关键指标"))
        #expect(writingPrompt.contains("# 与 13F 和后续信息的核对提示"))
        #expect(writingPrompt.contains("完整覆盖以下材料"))
    }

    @Test
    func rendersMarkdownWithoutLosingSummaryLineBreaks() {
        let markdown = """
        **一句话结论：**
        核心判断。

        **核心观点：**
        - 第一条
        - 第二条
        """

        let rendered = MarkdownTextParser.parse(markdown)
        let plainText = String(rendered.characters)

        #expect(!plainText.contains("**"))
        #expect(plainText.contains("\n\n"))
        #expect(plainText.contains("- 第一条\n- 第二条"))
        #expect(
            rendered.runs.contains {
                $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
            }
        )
    }

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

    @Test
    func identifiesLegacyAndDetailedSummaryFormats() {
        let legacy = AISummary(
            content: "一句话结论：内容很重要。",
            provider: .ollama,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let detailed = AISummary(
            content: """
            # 关键事实与数据
            - 事实
            # 主要观点与论证链
            - 观点
            # 原文覆盖说明
            - 已覆盖
            """,
            provider: .ollama,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(!legacy.isDetailedFormat)
        #expect(detailed.isDetailedFormat)
    }
}
