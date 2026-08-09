import Foundation

struct InvestorPreset: Identifiable, Hashable {
    enum HoldingsKind: String, Hashable {
        case sec13F
        case chineseFund
        case unavailable
    }

    var id: String
    var name: String
    var firm: String
    var style: String
    var cik: String
    var holdingsKind: HoldingsKind = .sec13F
    var fundCodes: [String] = []

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
        ),
        InvestorPreset(
            id: "zhang-kun",
            name: "张坤",
            firm: "易方达基金",
            style: "长期价值与高质量消费、互联网企业",
            cik: "",
            holdingsKind: .chineseFund,
            fundCodes: ["005827", "110011"]
        ),
        InvestorPreset(
            id: "fu-pengbo",
            name: "傅鹏博",
            firm: "睿远基金",
            style: "长期成长与价值创造",
            cik: "",
            holdingsKind: .chineseFund,
            fundCodes: ["007119"]
        ),
        InvestorPreset(
            id: "zhao-feng",
            name: "赵枫",
            firm: "睿远基金",
            style: "均衡价值与长期复利",
            cik: "",
            holdingsKind: .chineseFund,
            fundCodes: ["008969"]
        ),
        InvestorPreset(
            id: "liu-yanchun",
            name: "刘彦春",
            firm: "景顺长城基金",
            style: "消费与优秀企业长期持有",
            cik: "",
            holdingsKind: .chineseFund,
            fundCodes: ["260108"]
        ),
        InvestorPreset(
            id: "zhu-shaoxing",
            name: "朱少醒",
            firm: "富国基金",
            style: "长期成长与基本面研究",
            cik: "",
            holdingsKind: .chineseFund,
            fundCodes: ["161005"]
        ),
        InvestorPreset(
            id: "qiu-dongrong",
            name: "邱栋荣",
            firm: "中庚基金",
            style: "深度价值与逆向投资",
            cik: "",
            holdingsKind: .chineseFund,
            fundCodes: ["006551"]
        ),
        InvestorPreset(
            id: "lin-yuan",
            name: "林园",
            firm: "林园投资",
            style: "消费、医药与长期价值投资",
            cik: "",
            holdingsKind: .unavailable
        ),
        InvestorPreset(
            id: "dan-bin",
            name: "但斌",
            firm: "东方港湾海外基金",
            style: "全球优质企业与长期复利",
            cik: "2046333"
        ),
        InvestorPreset(
            id: "duan-yongping",
            name: "段永平",
            firm: "H&H International Investment",
            style: "商业模式、企业家与长期持有",
            cik: "1759760"
        ),
        InvestorPreset(
            id: "zhang-lei",
            name: "张磊",
            firm: "高瓴资本",
            style: "长期主义与产业投资",
            cik: "",
            holdingsKind: .unavailable
        )
    ]
}

struct InvestorPortfolio: Identifiable, Codable, Equatable {
    var investorID: String
    var reportDate: String
    var filingDate: String
    var totalValueUSD: Int64
    var positions: [InvestorPosition]
    var changes: [InvestorHoldingChange] = []
    var currencyCode: String = "USD"
    var refreshedAt: Date

    var id: String { investorID }

    enum CodingKeys: String, CodingKey {
        case investorID, reportDate, filingDate, totalValueUSD, positions, changes, currencyCode, refreshedAt
    }

    init(
        investorID: String,
        reportDate: String,
        filingDate: String,
        totalValueUSD: Int64,
        positions: [InvestorPosition],
        changes: [InvestorHoldingChange] = [],
        currencyCode: String = "USD",
        refreshedAt: Date
    ) {
        self.investorID = investorID
        self.reportDate = reportDate
        self.filingDate = filingDate
        self.totalValueUSD = totalValueUSD
        self.positions = positions
        self.changes = changes
        self.currencyCode = currencyCode
        self.refreshedAt = refreshedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            investorID: try container.decode(String.self, forKey: .investorID),
            reportDate: try container.decode(String.self, forKey: .reportDate),
            filingDate: try container.decode(String.self, forKey: .filingDate),
            totalValueUSD: try container.decode(Int64.self, forKey: .totalValueUSD),
            positions: try container.decode([InvestorPosition].self, forKey: .positions),
            changes: try container.decodeIfPresent([InvestorHoldingChange].self, forKey: .changes) ?? [],
            currencyCode: try container.decodeIfPresent(String.self, forKey: .currencyCode) ?? "USD",
            refreshedAt: try container.decode(Date.self, forKey: .refreshedAt)
        )
    }
}

struct InvestorHoldingChange: Codable, Equatable, Identifiable {
    var securityKey: String
    var issuer: String
    var titleOfClass: String
    var cusip: String
    var ticker: String?
    var localizedName: String? = nil
    var putCall: String?
    var kind: HoldingChangeKind
    var oldShares: Double
    var newShares: Double
    var oldValueUSD: Int64
    var newValueUSD: Int64

    var id: String { securityKey }
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
        let previous = history
            .filter { $0.reportDate < latest.reportDate }
            .max { $0.reportDate < $1.reportDate }
        let changes = previous.map {
            HoldingsDiffer.changes(old: $0.holdings, new: latest.holdings).map {
                InvestorHoldingChange(
                    securityKey: $0.holding.key,
                    issuer: $0.holding.issuer,
                    titleOfClass: $0.holding.titleOfClass,
                    cusip: $0.holding.cusip,
                    ticker: cachedTickers[$0.holding.cusip],
                    putCall: $0.holding.putCall,
                    kind: $0.kind,
                    oldShares: $0.oldShares,
                    newShares: $0.newShares,
                    oldValueUSD: $0.oldValueUSD,
                    newValueUSD: $0.newValueUSD
                )
            }
        } ?? []

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
            changes: changes,
            currencyCode: "USD",
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

struct InvestorConsensus: Identifiable, Equatable {
    var securityKey: String
    var issuer: String
    var titleOfClass: String
    var cusip: String
    var ticker: String?
    var localizedName: String?
    var holderCount: Int
    var aggregateWeight: Double
    var currentInvestors: [String]
    var buyers: [String]
    var sellers: [String]
    var latestValueUSD: Int64
    var currencyCode: String?

    var id: String { securityKey }

    var signalTitle: String {
        if !buyers.isEmpty && sellers.isEmpty {
            return buyers.count >= 2 ? "一致买入" : "买入"
        }
        if !sellers.isEmpty && buyers.isEmpty {
            return sellers.count >= 2 ? "一致卖出" : "卖出"
        }
        if buyers.count > sellers.count { return "买入占优" }
        if sellers.count > buyers.count { return "卖出占优" }
        return "分歧"
    }
}

enum InvestorConsensusBuilder {
    static func build(
        investors: [InvestorPreset],
        portfolios: [String: InvestorPortfolio]
    ) -> [InvestorConsensus] {
        struct Accumulator {
            var securityKey: String
            var issuer = ""
            var titleOfClass = ""
            var cusip = ""
            var ticker: String?
            var localizedName: String?
            var holderIDs = Set<String>()
            var aggregateWeight = 0.0
            var currentInvestors = Set<String>()
            var buyers = Set<String>()
            var sellers = Set<String>()
            var latestValueUSD: Int64 = 0
            var currencyCodes = Set<String>()
        }

        var accumulators: [String: Accumulator] = [:]
        for investor in investors {
            guard let portfolio = portfolios[investor.id] else { continue }

            for position in portfolio.positions where position.putCall == nil {
                var accumulator = accumulators[position.securityKey] ?? Accumulator(securityKey: position.securityKey)
                accumulator.issuer = position.issuer
                accumulator.titleOfClass = position.titleOfClass
                accumulator.cusip = position.cusip
                accumulator.ticker = position.ticker ?? accumulator.ticker
                accumulator.localizedName = position.localizedName ?? accumulator.localizedName
                accumulator.holderIDs.insert(investor.id)
                accumulator.currentInvestors.insert(investor.name)
                accumulator.aggregateWeight += position.portfolioWeight
                accumulator.latestValueUSD += position.valueUSD
                accumulator.currencyCodes.insert(portfolio.currencyCode)
                accumulators[position.securityKey] = accumulator
            }

            for change in portfolio.changes where change.putCall == nil {
                var accumulator = accumulators[change.securityKey] ?? Accumulator(securityKey: change.securityKey)
                accumulator.issuer = change.issuer
                accumulator.titleOfClass = change.titleOfClass
                accumulator.cusip = change.cusip
                accumulator.ticker = change.ticker ?? accumulator.ticker
                accumulator.localizedName = change.localizedName ?? accumulator.localizedName
                accumulator.currencyCodes.insert(portfolio.currencyCode)
                switch change.kind {
                case .added, .increased:
                    accumulator.buyers.insert(investor.name)
                case .exited, .decreased:
                    accumulator.sellers.insert(investor.name)
                }
                accumulators[change.securityKey] = accumulator
            }
        }

        return accumulators.values
            .filter { !$0.buyers.isEmpty || !$0.sellers.isEmpty }
            .map {
                InvestorConsensus(
                    securityKey: $0.securityKey,
                    issuer: $0.issuer,
                    titleOfClass: $0.titleOfClass,
                    cusip: $0.cusip,
                    ticker: $0.ticker,
                    localizedName: $0.localizedName,
                    holderCount: $0.holderIDs.count,
                    aggregateWeight: $0.aggregateWeight,
                    currentInvestors: $0.currentInvestors.sorted(),
                    buyers: $0.buyers.sorted(),
                    sellers: $0.sellers.sorted(),
                    latestValueUSD: $0.currencyCodes.count == 1 ? $0.latestValueUSD : 0,
                    currencyCode: $0.currencyCodes.count == 1 ? $0.currencyCodes.first : nil
                )
            }
            .sorted {
                let lhsNet = abs($0.buyers.count - $0.sellers.count)
                let rhsNet = abs($1.buyers.count - $1.sellers.count)
                if lhsNet != rhsNet { return lhsNet > rhsNet }
                if $0.holderCount != $1.holderCount { return $0.holderCount > $1.holderCount }
                if $0.aggregateWeight != $1.aggregateWeight { return $0.aggregateWeight > $1.aggregateWeight }
                return ($0.ticker ?? $0.issuer) < ($1.ticker ?? $1.issuer)
            }
    }
}
