import Foundation

struct InvestorPreset: Identifiable, Hashable {
    var id: String
    var name: String
    var firm: String
    var style: String
    var cik: String

    static let featured: [InvestorPreset] = [
        InvestorPreset(
            id: "warren-buffett",
            name: "Warren Buffett",
            firm: "Berkshire Hathaway",
            style: "长期价值与高质量企业",
            cik: "1067983"
        ),
        InvestorPreset(
            id: "bill-ackman",
            name: "Bill Ackman",
            firm: "Pershing Square",
            style: "集中持仓与积极股东策略",
            cik: "1336528"
        ),
        InvestorPreset(
            id: "ray-dalio",
            name: "Ray Dalio",
            firm: "Bridgewater Associates",
            style: "全球宏观、经济周期与风险平价",
            cik: "1350694"
        ),
        InvestorPreset(
            id: "seth-klarman",
            name: "Seth Klarman",
            firm: "Baupost Group",
            style: "安全边际与特殊机会",
            cik: "1061768"
        ),
        InvestorPreset(
            id: "stanley-druckenmiller",
            name: "Stanley Druckenmiller",
            firm: "Duquesne Family Office",
            style: "宏观趋势与集中选股",
            cik: "1536411"
        ),
        InvestorPreset(
            id: "david-tepper",
            name: "David Tepper",
            firm: "Appaloosa",
            style: "困境反转与宏观机会",
            cik: "1656456"
        ),
        InvestorPreset(
            id: "michael-burry",
            name: "Michael Burry",
            firm: "Scion Asset Management",
            style: "逆向投资与非共识机会",
            cik: "1649339"
        ),
        InvestorPreset(
            id: "david-einhorn",
            name: "David Einhorn",
            firm: "Greenlight Capital",
            style: "价值投资与多空研究",
            cik: "1079114"
        ),
        InvestorPreset(
            id: "li-lu",
            name: "Li Lu",
            firm: "Himalaya Capital",
            style: "长期价值与高确定性复利",
            cik: "1709323"
        ),
        InvestorPreset(
            id: "mohnish-pabrai",
            name: "Mohnish Pabrai",
            firm: "Dalal Street",
            style: "集中价值与低风险高不确定性",
            cik: "1549575"
        ),
        InvestorPreset(
            id: "terry-smith",
            name: "Terry Smith",
            firm: "Fundsmith",
            style: "高资本回报率企业长期持有",
            cik: "1569205"
        ),
        InvestorPreset(
            id: "chris-hohn",
            name: "Chris Hohn",
            firm: "TCI Fund Management",
            style: "集中质量投资与积极治理",
            cik: "1647251"
        ),
        InvestorPreset(
            id: "chuck-akre",
            name: "Chuck Akre",
            firm: "Akre Capital Management",
            style: "优秀商业、优秀管理与再投资",
            cik: "1112520"
        )
    ]
}

struct InvestorPortfolio: Identifiable, Codable, Equatable {
    var investorID: String
    var reportDate: String
    var filingDate: String
    var totalValueUSD: Int64
    var positions: [InvestorPosition]
    var refreshedAt: Date

    var id: String { investorID }
}

struct InvestorPosition: Identifiable, Codable, Equatable {
    var securityKey: String
    var issuer: String
    var titleOfClass: String
    var cusip: String
    var ticker: String?
    var localizedName: String? = nil
    var shares: Double
    var valueUSD: Int64
    var portfolioWeight: Double
    var putCall: String?
    var latestPrice: Double?
    var estimatedCost: Double?
    var estimatedProfitLoss: Double?
    var costConfidence: CostConfidence?
    var returns: AnnualizedReturns
    var marketDataAsOf: Date?

    var id: String { securityKey }

    var chineseName: String? {
        guard let localizedName,
              localizedName.range(of: #"\p{Han}"#, options: .regularExpression) != nil else {
            return nil
        }
        return localizedName
    }

    var xueqiuURL: URL? {
        guard putCall == nil,
              let ticker = ticker?.trimmingCharacters(in: .whitespacesAndNewlines),
              !ticker.isEmpty else {
            return nil
        }
        return URL(string: "https://xueqiu.com")?
            .appending(path: "S")
            .appending(path: ticker.uppercased())
    }
}

enum CostConfidence: String, Codable {
    case medium
    case low

    var title: String {
        switch self {
        case .medium: "中等置信"
        case .low: "低置信"
        }
    }
}

struct AnnualizedReturns: Codable, Equatable {
    var oneYear: Double? = nil
    var threeYears: Double? = nil
    var fiveYears: Double? = nil
    var tenYears: Double? = nil

    static let empty = AnnualizedReturns()
}

struct MarketPricePoint: Codable, Equatable {
    var date: Date
    var close: Double
}

struct CostEstimate: Equatable {
    var price: Double
    var confidence: CostConfidence
}

enum PortfolioAnalytics {
    static func basePortfolio(
        investor: InvestorPreset,
        history: [ReportedPortfolio],
        cachedTickers: [String: String] = [:]
    ) -> InvestorPortfolio? {
        guard let latest = history.max(by: { $0.reportDate < $1.reportDate }) else { return nil }
        let holdings = aggregate(latest.holdings)
            .sorted { $0.valueUSD > $1.valueUSD }
        let totalValue = holdings.reduce(Int64(0)) { $0 + $1.valueUSD }

        let positions = holdings.map { holding in
            InvestorPosition(
                securityKey: holding.key,
                issuer: holding.issuer,
                titleOfClass: holding.titleOfClass,
                cusip: holding.cusip,
                ticker: cachedTickers[holding.cusip],
                shares: holding.shares,
                valueUSD: holding.valueUSD,
                portfolioWeight: totalValue > 0 ? Double(holding.valueUSD) / Double(totalValue) : 0,
                putCall: holding.putCall,
                latestPrice: nil,
                estimatedCost: nil,
                estimatedProfitLoss: nil,
                costConfidence: nil,
                returns: .empty,
                marketDataAsOf: nil
            )
        }

        return InvestorPortfolio(
            investorID: investor.id,
            reportDate: latest.reportDate,
            filingDate: latest.filingDate,
            totalValueUSD: totalValue,
            positions: positions,
            refreshedAt: Date()
        )
    }

    static func estimatedCost(
        for securityKey: String,
        history: [ReportedPortfolio],
        prices: [MarketPricePoint]
    ) -> CostEstimate? {
        guard !prices.isEmpty else { return nil }
        let orderedHistory = history.sorted { $0.reportDate < $1.reportDate }
        var previousShares = 0.0
        var averageCost: Double?
        var observedPriorQuarter = false
        var openedWithinHistory = false

        for report in orderedHistory {
            let current = aggregate(report.holdings).first { $0.key == securityKey }
            guard let current, current.shares > 0 else {
                previousShares = 0
                averageCost = nil
                observedPriorQuarter = true
                continue
            }
            guard let date = SECDateParser.date(report.reportDate),
                  let reportPrice = price(near: date, in: prices) else {
                previousShares = current.shares
                observedPriorQuarter = true
                continue
            }
            let currentShares = splitAdjustedShares(
                holding: current,
                adjustedPrice: reportPrice
            )

            if previousShares == 0 || averageCost == nil {
                averageCost = reportPrice
                openedWithinHistory = observedPriorQuarter
            } else if currentShares > previousShares, let existingCost = averageCost {
                let addedShares = currentShares - previousShares
                let priorCost = previousShares * existingCost
                let addedCost = addedShares * reportPrice
                averageCost = (priorCost + addedCost) / currentShares
            }

            previousShares = currentShares
            observedPriorQuarter = true
        }

        guard let averageCost, averageCost > 0 else { return nil }
        return CostEstimate(
            price: averageCost,
            confidence: openedWithinHistory ? .medium : .low
        )
    }

    static func annualizedReturns(prices: [MarketPricePoint]) -> AnnualizedReturns {
        AnnualizedReturns(
            oneYear: annualizedReturn(prices: prices, years: 1),
            threeYears: annualizedReturn(prices: prices, years: 3),
            fiveYears: annualizedReturn(prices: prices, years: 5),
            tenYears: annualizedReturn(prices: prices, years: 10)
        )
    }

    static func annualizedReturn(prices: [MarketPricePoint], years: Int) -> Double? {
        let ordered = prices
            .filter { $0.close > 0 }
            .sorted { $0.date < $1.date }
        guard let latest = ordered.last,
              let target = Calendar(identifier: .gregorian).date(
                byAdding: .year,
                value: -years,
                to: latest.date
              ),
              let start = ordered.min(by: {
                  abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target))
              }),
              abs(start.date.timeIntervalSince(target)) <= 62 * 24 * 60 * 60 else {
            return nil
        }

        let elapsedYears = latest.date.timeIntervalSince(start.date) / (365.2425 * 24 * 60 * 60)
        guard elapsedYears > 0.8 * Double(years) else { return nil }
        return pow(latest.close / start.close, 1 / elapsedYears) - 1
    }

    private static func aggregate(_ holdings: [Holding]) -> [Holding] {
        Array(
            holdings.reduce(into: [String: Holding]()) { result, holding in
                if result[holding.key] == nil {
                    result[holding.key] = holding
                } else {
                    result[holding.key]?.shares += holding.shares
                    result[holding.key]?.valueUSD += holding.valueUSD
                }
            }.values
        )
    }

    private static func price(near date: Date, in prices: [MarketPricePoint]) -> Double? {
        prices
            .filter { $0.close > 0 }
            .min { lhs, rhs in
                abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
            }
            .flatMap {
                abs($0.date.timeIntervalSince(date)) <= 62 * 24 * 60 * 60 ? $0.close : nil
            }
    }

    private static func splitAdjustedShares(
        holding: Holding,
        adjustedPrice: Double
    ) -> Double {
        guard holding.shares > 0, holding.valueUSD > 0, adjustedPrice > 0 else {
            return holding.shares
        }
        let reportedPrice = Double(holding.valueUSD) / holding.shares
        let observedFactor = reportedPrice / adjustedPrice
        let commonFactors = [
            0.1, 0.2, 0.25, 1.0 / 3.0, 0.5,
            1, 1.5, 2, 3, 4, 5, 10
        ]
        guard let factor = commonFactors.min(by: {
            abs(log($0 / observedFactor)) < abs(log($1 / observedFactor))
        }),
        abs(factor / observedFactor - 1) <= 0.12 else {
            return holding.shares
        }
        return holding.shares * factor
    }
}
