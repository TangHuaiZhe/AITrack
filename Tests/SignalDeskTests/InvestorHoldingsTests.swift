import Foundation
import Testing
@testable import SignalDesk

struct InvestorHoldingsTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TRACKAI_LIVE_SEC_TEST"] == "1"))
    func fetchesLiveBerkshirePortfolioHistory() async throws {
        let investor = try #require(
            InvestorPreset.featured.first { $0.id == "warren-buffett" }
        )

        let context = try await InvestorPortfolioService().fetchBasePortfolio(
            for: investor,
            cachedTickers: [:]
        )

        #expect(context.history.count >= 2)
        #expect(context.portfolio.positions.count > 10)
        #expect(context.portfolio.totalValueUSD > 100_000_000_000)
        #expect(context.portfolio.totalValueUSD < 1_000_000_000_000)
    }

    @Test func calculatesPortfolioWeights() throws {
        let investor = try #require(InvestorPreset.featured.first)
        let history = [
            ReportedPortfolio(
                reportDate: "2026-03-31",
                filingDate: "2026-05-15",
                holdings: [
                    holding("A", cusip: "1", shares: 100, value: 3_000),
                    holding("B", cusip: "2", shares: 50, value: 1_000)
                ]
            )
        ]

        let portfolio = try #require(
            PortfolioAnalytics.basePortfolio(investor: investor, history: history)
        )

        #expect(portfolio.totalValueUSD == 4_000)
        #expect(portfolio.positions[0].portfolioWeight == 0.75)
        #expect(portfolio.positions[1].portfolioWeight == 0.25)
    }

    @Test func estimatesWeightedCostFromQuarterlyAdds() throws {
        let history = [
            report("2020-12-31", holdings: []),
            report("2021-03-31", holdings: [holding("A", cusip: "1", shares: 100, value: 1_000)]),
            report("2021-06-30", holdings: [holding("A", cusip: "1", shares: 150, value: 3_000)]),
            report("2021-09-30", holdings: [holding("A", cusip: "1", shares: 120, value: 3_600)])
        ]
        let prices = [
            price("2021-03-31", close: 10),
            price("2021-06-30", close: 20),
            price("2021-09-30", close: 30)
        ]

        let estimate = try #require(
            PortfolioAnalytics.estimatedCost(
                for: "1|COM|",
                history: history,
                prices: prices
            )
        )

        #expect(abs(estimate.price - 13.333_333) < 0.001)
        #expect(estimate.confidence == .medium)
    }

    @Test func calculatesOneThreeFiveAndTenYearCAGR() throws {
        let prices = [
            price("2016-01-01", close: 100),
            price("2021-01-01", close: 161.051),
            price("2023-01-01", close: 194.872),
            price("2025-01-01", close: 235.795),
            price("2026-01-01", close: 259.374)
        ]

        let returns = PortfolioAnalytics.annualizedReturns(prices: prices)

        #expect(abs(try #require(returns.oneYear) - 0.10) < 0.001)
        #expect(abs(try #require(returns.threeYears) - 0.10) < 0.001)
        #expect(abs(try #require(returns.fiveYears) - 0.10) < 0.001)
        #expect(abs(try #require(returns.tenYears) - 0.10) < 0.001)
    }

    @Test func doesNotTreatStockSplitAsPositionAddition() throws {
        let history = [
            report("2021-03-31", holdings: [
                holding("A", cusip: "1", shares: 100, value: 20_000)
            ]),
            report("2021-06-30", holdings: [
                holding("A", cusip: "1", shares: 400, value: 28_000)
            ]),
            report("2021-09-30", holdings: [
                holding("A", cusip: "1", shares: 500, value: 50_000)
            ])
        ]
        let splitAdjustedPrices = [
            price("2021-03-31", close: 50),
            price("2021-06-30", close: 70),
            price("2021-09-30", close: 100)
        ]

        let estimate = try #require(
            PortfolioAnalytics.estimatedCost(
                for: "1|COM|",
                history: history,
                prices: splitAdjustedPrices
            )
        )

        #expect(abs(estimate.price - 60) < 0.001)
    }

    @Test func leavesLongHorizonEmptyWhenHistoryIsMissing() {
        let prices = [
            price("2023-01-01", close: 100),
            price("2026-01-01", close: 121)
        ]

        let returns = PortfolioAnalytics.annualizedReturns(prices: prices)

        #expect(returns.threeYears != nil)
        #expect(returns.fiveYears == nil)
        #expect(returns.tenYears == nil)
    }

    @Test func parsesSingleTwelveDataSeries() throws {
        let data = Data(
            """
            {
              "meta": {"symbol": "AAPL"},
              "values": [
                {"datetime": "2025-01-31", "close": "200.50"},
                {"datetime": "2025-02-28", "close": "210.25"}
              ],
              "status": "ok"
            }
            """.utf8
        )

        let parsed = try TwelveDataClient.parseTimeSeries(
            data: data,
            requestedSymbols: ["AAPL"]
        )

        #expect(parsed["AAPL"]?.count == 2)
        #expect(parsed["AAPL"]?.last?.close == 210.25)
    }

    @Test func parsesBatchTwelveDataSeries() throws {
        let data = Data(
            """
            {
              "AAPL": {
                "values": [{"datetime": "2025-01-31", "close": "200"}],
                "status": "ok"
              },
              "MSFT": {
                "values": [{"datetime": "2025-01-31", "close": "400"}],
                "status": "ok"
              }
            }
            """.utf8
        )

        let parsed = try TwelveDataClient.parseTimeSeries(
            data: data,
            requestedSymbols: ["AAPL", "MSFT"]
        )

        #expect(parsed["AAPL"]?.first?.close == 200)
        #expect(parsed["MSFT"]?.first?.close == 400)
    }

    @Test func skipsUnavailableSymbolInTwelveDataBatch() throws {
        let data = Data(
            """
            {
              "AAPL": {
                "values": [{"datetime": "2025-01-31", "close": "200"}],
                "status": "ok"
              },
              "DELISTED": {
                "status": "error",
                "message": "symbol not found"
              }
            }
            """.utf8
        )

        let parsed = try TwelveDataClient.parseTimeSeries(
            data: data,
            requestedSymbols: ["AAPL", "DELISTED"]
        )

        #expect(parsed["AAPL"]?.first?.close == 200)
        #expect(parsed["DELISTED"] == nil)
    }

    private func report(_ date: String, holdings: [Holding]) -> ReportedPortfolio {
        ReportedPortfolio(reportDate: date, filingDate: date, holdings: holdings)
    }

    private func price(_ date: String, close: Double) -> MarketPricePoint {
        MarketPricePoint(date: SECDateParser.date(date)!, close: close)
    }

    private func holding(
        _ issuer: String,
        cusip: String,
        shares: Double,
        value: Int64
    ) -> Holding {
        Holding(
            issuer: issuer,
            titleOfClass: "COM",
            cusip: cusip,
            valueUSD: value,
            shares: shares,
            putCall: nil
        )
    }
}
