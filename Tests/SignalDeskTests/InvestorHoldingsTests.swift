import Foundation
import Testing
@testable import SignalDesk

struct InvestorHoldingsTests {
    @Test @MainActor
    func portfolioCacheUsesThirtyDayValidityWindow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fresh = now.addingTimeInterval(-29 * 24 * 60 * 60)
        let stale = now.addingTimeInterval(-30 * 24 * 60 * 60)

        #expect(InvestorHoldingsStore.isPortfolioCacheFresh(refreshedAt: fresh, now: now))
        #expect(!InvestorHoldingsStore.isPortfolioCacheFresh(refreshedAt: stale, now: now))
    }

    @Test
    func includesRayDalioBridgewater13F() throws {
        let investor = try #require(
            InvestorPreset.featured.first { $0.id == "ray-dalio" }
        )

        #expect(investor.name == "Ray Dalio")
        #expect(investor.firm == "Bridgewater Associates")
        #expect(investor.cik == "1350694")
    }

    @Test
    func includesChineseFundManagersAndSeparatesUnavailablePrivateHoldings() throws {
        let zhangKun = try #require(
            InvestorPreset.featured.first { $0.id == "zhang-kun" }
        )
        let duanYongping = try #require(
            InvestorPreset.featured.first { $0.id == "duan-yongping" }
        )
        let danBin = try #require(
            InvestorPreset.featured.first { $0.id == "dan-bin" }
        )

        #expect(zhangKun.holdingsKind == .chineseFund)
        #expect(zhangKun.fundCodes == ["005827", "110011"])
        #expect(duanYongping.holdingsKind == .sec13F)
        #expect(duanYongping.cik == "1759760")
        #expect(danBin.holdingsKind == .sec13F)
        #expect(danBin.cik == "2046333")
        #expect(InvestorPreset.featured.contains { $0.id == "lin-yuan" })
        #expect(InvestorPreset.featured.contains { $0.id == "dan-bin" })
        #expect(InvestorPreset.featured.contains { $0.id == "zhang-lei" })
    }

    @Test
    func parsesChineseFundTopTenHoldings() throws {
        let data = Data(
            #"""
            var apidata={ content:"<div class='boxitem'><h4>截止至：<font class='px12'>2026-06-30</font></h4><table><tbody><tr><td>1</td><td class='toc'><a href='//quote.eastmoney.com/unify/r/1.600519'>600519</a></td><td><a>贵州茅台</a></td><td>--</td><td>--</td><td>--</td><td>9.23%</td><td>52.77</td><td>62,558.31</td></tr></tbody></table></div><div class='boxitem'><h4>截止至：<font class='px12'>2026-03-31</font></h4><table><tbody><tr><td>1</td><td><a href='//quote.eastmoney.com/unify/r/1.600519'>600519</a></td><td>贵州茅台</td><td>9.91%</td><td>183.20</td><td>265,640.00</td></tr></tbody></table></div>",arryear:[2026]};
            """#.utf8
        )

        let reports = try ChinaFundHoldingsClient.parse(data: data)
        let holding = try #require(reports.first?.holdings.first)

        #expect(reports.count == 2)
        #expect(reports.first?.reportDate == "2026-06-30")
        #expect(holding.cusip == "1.600519")
        #expect(holding.issuer == "贵州茅台")
        #expect(holding.valueUSD == 625_583_100)
        #expect(holding.shares == 527_700)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TRACKAI_LIVE_CHINA_FUND_TEST"] == "1"))
    func fetchesLiveChineseFundHoldings() async throws {
        let investor = try #require(
            InvestorPreset.featured.first { $0.id == "zhang-kun" }
        )
        let context = try await InvestorPortfolioService().fetchBasePortfolio(
            for: investor,
            cachedTickers: [:]
        )

        #expect(context.history.count >= 2)
        #expect(context.portfolio.currencyCode == "CNY")
        #expect(context.portfolio.positions.count > 5)
        #expect(context.portfolio.positions.allSatisfy { $0.ticker != nil })
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TRACKAI_LIVE_CHINA_FUND_TEST"] == "1"))
    func fetchesLiveHoldingsForEveryChineseFundManager() async throws {
        let ids = ["fu-pengbo", "zhao-feng", "liu-yanchun", "zhu-shaoxing", "qiu-dongrong"]
        for id in ids {
            let investor = try #require(InvestorPreset.featured.first { $0.id == id })
            let context = try await InvestorPortfolioService().fetchBasePortfolio(
                for: investor,
                cachedTickers: [:]
            )
            #expect(context.history.count >= 2)
            #expect(context.portfolio.positions.count > 5)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TRACKAI_LIVE_SEC_TEST"] == "1"))
    func fetchesLiveDanBinOrientalHarbor13F() async throws {
        let investor = try #require(
            InvestorPreset.featured.first { $0.id == "dan-bin" }
        )
        let context = try await InvestorPortfolioService().fetchBasePortfolio(
            for: investor,
            cachedTickers: [:]
        )

        #expect(context.history.count >= 2)
        #expect(context.portfolio.positions.count >= 5)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TRACKAI_LIVE_SEC_TEST"] == "1"))
    func fetchesLiveDuanYongping13F() async throws {
        let investor = try #require(
            InvestorPreset.featured.first { $0.id == "duan-yongping" }
        )
        let context = try await InvestorPortfolioService().fetchBasePortfolio(
            for: investor,
            cachedTickers: [:]
        )

        #expect(context.history.count >= 2)
        #expect(context.portfolio.positions.count >= 5)
    }

    @Test
    func parsesChineseSecurityNamesAndBuildsXueqiuURL() throws {
        let data = Data(
            """
            {
              "data": {
                "diff": [
                  {"f12": "AAPL", "f14": "苹果"},
                  {"f12": "PDD", "f14": "拼多多"},
                  {"f12": "ALLY", "f14": "Ally Financial Inc"}
                ]
              }
            }
            """.utf8
        )

        let names = try ChineseSecurityNameClient.parse(data: data)
        let position = InvestorPosition(
            securityKey: "037833100|COM|",
            issuer: "Apple Inc",
            titleOfClass: "COM",
            cusip: "037833100",
            ticker: "AAPL",
            shares: 10,
            valueUSD: 1_000,
            portfolioWeight: 1,
            putCall: nil,
            latestPrice: nil,
            estimatedCost: nil,
            estimatedProfitLoss: nil,
            costConfidence: nil,
            returns: .empty,
            marketDataAsOf: nil
        )
        let url = try #require(position.xueqiuURL)

        #expect(names["AAPL"] == "苹果")
        #expect(names["PDD"] == "拼多多")
        #expect(names["ALLY"] == nil)
        #expect(url.absoluteString == "https://xueqiu.com/S/AAPL")
    }

    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["TRACKAI_LIVE_CHINESE_NAME_TEST"] == "1"
    ))
    func fetchesLiveChineseSecurityNames() async throws {
        let names = try await ChineseSecurityNameClient().names(
            for: ["AAPL", "PDD", "BRK.B"]
        )

        #expect(names["AAPL"] == "苹果")
        #expect(names["PDD"] == "拼多多")
        #expect(names["BRK.B"] == "伯克希尔-哈撒韦B")
    }

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

    @Test func aggregatesInvestorConsensusFromLatestQuarterChanges() throws {
        let investors = Array(InvestorPreset.featured.prefix(3))
        let aaplKey = "037833100|COM|"
        let portfolios = Dictionary(uniqueKeysWithValues: investors.enumerated().map { index, investor in
            let isCurrentHolder = index < 2
            let position = InvestorPosition(
                securityKey: aaplKey,
                issuer: "Apple Inc",
                titleOfClass: "COM",
                cusip: "037833100",
                ticker: "AAPL",
                localizedName: "苹果",
                shares: 100,
                valueUSD: isCurrentHolder ? 10_000 : 0,
                portfolioWeight: isCurrentHolder ? 0.25 : 0,
                putCall: nil,
                latestPrice: nil,
                estimatedCost: nil,
                estimatedProfitLoss: nil,
                costConfidence: nil,
                returns: .empty,
                marketDataAsOf: nil
            )
            let change = InvestorHoldingChange(
                securityKey: aaplKey,
                issuer: "Apple Inc",
                titleOfClass: "COM",
                cusip: "037833100",
                ticker: "AAPL",
                localizedName: "苹果",
                putCall: nil,
                kind: index == 2 ? .decreased : .increased,
                oldShares: index == 2 ? 200 : 80,
                newShares: 100,
                oldValueUSD: index == 2 ? 20_000 : 8_000,
                newValueUSD: isCurrentHolder ? 10_000 : 0
            )
            return (
                investor.id,
                InvestorPortfolio(
                    investorID: investor.id,
                    reportDate: "2026-03-31",
                    filingDate: "2026-05-15",
                    totalValueUSD: 40_000,
                    positions: isCurrentHolder ? [position] : [],
                    changes: [change],
                    refreshedAt: Date()
                )
            )
        })

        let item = try #require(
            InvestorConsensusBuilder.build(investors: investors, portfolios: portfolios).first
        )

        #expect(item.ticker == "AAPL")
        #expect(item.localizedName == "苹果")
        #expect(item.holderCount == 2)
        #expect(item.buyers.count == 2)
        #expect(item.sellers.count == 1)
        #expect(item.signalTitle == "买入占优")
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
