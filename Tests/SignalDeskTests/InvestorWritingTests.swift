import AppKit
import Foundation
import Testing
@testable import SignalDesk

struct InvestorWritingTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TRACKAI_LIVE_WRITING_TEST"] == "1"))
    func fetchesLiveOfficialWritingSources() async throws {
        let ackman = try #require(
            InvestorPreset.featured.first { $0.id == "bill-ackman" }
        )
        let akre = try #require(
            InvestorPreset.featured.first { $0.id == "chuck-akre" }
        )

        let ackmanWritings = try await InvestorWritingClient().fetch(for: ackman)
        let akreWritings = try await InvestorWritingClient().fetch(for: akre)
        let firstBerkshireLetter = try #require(
            InvestorWritingCatalog.curated(for: "warren-buffett")
                .first { $0.period == "1977" }
        )
        let firstLetterText = await ArticleContentFetcher().content(
            title: firstBerkshireLetter.title,
            summary: firstBerkshireLetter.sourceNote,
            rawURL: firstBerkshireLetter.sourceURL
        )

        #expect(ackmanWritings.count >= 2)
        #expect(akreWritings.count >= 2)
        #expect(ackmanWritings.allSatisfy { $0.sourceURL.hasPrefix("https://") })
        #expect(akreWritings.allSatisfy { $0.attribution == .officialTeam })
        #expect(firstLetterText.count > 1_000)
        #expect(firstLetterText.localizedCaseInsensitiveContains("Berkshire"))
    }

    @Test
    func parsesPershingOfficialMaterialsAndFiltersUnrelatedDocuments() throws {
        let html = """
        <ul>
          <li class="materials--list--item 2026 letters-presentations">
            <span class="materials--list--item--date">February 18, 2026</span>
            <span class="materials--list--item--description">Letter to Shareholders in the 2025 Annual Report</span>
            <span class="materials--list--item--link">
              <a href="https://example.com/letter.pdf">PDF</a>
            </span>
          </li>
          <li class="materials--list--item 2026 fact-sheets">
            <span class="materials--list--item--date">February 13, 2026</span>
            <span class="materials--list--item--description">January 2026 Fact Sheet</span>
            <span class="materials--list--item--link">
              <a href="https://example.com/factsheet.pdf">PDF</a>
            </span>
          </li>
        </ul>
        """

        let writings = InvestorWritingClient.parsePershingMaterials(html: html)

        #expect(writings.count == 1)
        #expect(writings.first?.title == "Letter to Shareholders in the 2025 Annual Report")
        #expect(writings.first?.period == "2025")
        #expect(writings.first?.sourceURL == "https://example.com/letter.pdf")
        #expect(writings.first?.attribution == .officialTeam)
    }

    @Test
    func exposesOnlyVerifiedOfficialArchives() {
        #expect(InvestorWritingCatalog.archiveURL(for: "warren-buffett") != nil)
        #expect(InvestorWritingCatalog.archiveURL(for: "bill-ackman") != nil)
        #expect(InvestorWritingCatalog.archiveURL(for: "terry-smith") != nil)
        #expect(InvestorWritingCatalog.archiveURL(for: "chuck-akre") != nil)
        #expect(InvestorWritingCatalog.archiveURL(for: "michael-burry") == nil)
    }

    @Test
    func includesEveryOfficialBerkshireLetterFrom1977Through2024() {
        let letters = InvestorWritingCatalog.curated(for: "warren-buffett")
        let years = Set(letters.compactMap(\.period))
        let expectedYears = Set((1977...2024).map(String.init))

        #expect(letters.count == 48)
        #expect(years == expectedYears)
        #expect(letters.allSatisfy { $0.author == "Warren Buffett" })
        #expect(letters.allSatisfy { $0.attribution == .namedAuthor })
        #expect(letters.allSatisfy { $0.displaysYearOnly == true })
        #expect(letters.allSatisfy {
            $0.sourceURL.hasPrefix("https://www.berkshirehathaway.com/letters/")
        })
        #expect(
            letters.first { $0.period == "1977" }?.sourceURL.hasSuffix("/1977.html")
                == true
        )
        #expect(
            letters.first { $0.period == "2003" }?.sourceURL.hasSuffix("/2003.html")
                == true
        )
        #expect(
            letters.first { $0.period == "2004" }?.sourceURL.hasSuffix("/2004ltr.pdf")
                == true
        )
        #expect(
            letters.first { $0.period == "2024" }?.sourceURL.hasSuffix("/2024ltr.pdf")
                == true
        )
    }

    @Test @MainActor
    func writingSummaryPersistsInIndependentCache() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let stateURL = directory.appending(path: "writings.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = InvestorWritingStore(stateURL: stateURL)
        let writing = try #require(store.writings(for: "warren-buffett").first)
        let summary = AISummary(
            content: "一句话结论：保持耐心。",
            provider: .ollama,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let translation = AITranslation(
            content: "翻译：保持耐心。",
            provider: .ollama,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        store.saveSummary(
            summary,
            writingID: writing.id,
            investorID: writing.investorID
        )
        store.saveTranslation(
            translation,
            writingID: writing.id,
            investorID: writing.investorID
        )
        let reloaded = InvestorWritingStore(stateURL: stateURL)

        #expect(
            reloaded.writing(id: writing.id, investorID: writing.investorID)?.aiSummary
                == summary
        )
        #expect(
            reloaded.writing(id: writing.id, investorID: writing.investorID)?.aiTranslation
                == translation
        )
    }

    @Test @MainActor
    func extractsSelectableTextFromPDF() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
        textView.string = "Fund letter: we added to the position at an attractive valuation."
        let data = textView.dataWithPDF(inside: textView.bounds)

        let extracted = ArticleContentFetcher.extractPDFText(from: data)

        #expect(extracted.contains("we added to the position"))
    }
}
