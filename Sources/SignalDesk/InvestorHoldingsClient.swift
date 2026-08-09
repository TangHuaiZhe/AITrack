import Combine
import Foundation

struct PortfolioRefreshContext {
    var portfolio: InvestorPortfolio
    var history: [ReportedPortfolio]
}

enum InvestorHoldingsError: LocalizedError {
    case holdingsUnavailable
    case informationUnavailable
    case insufficientFilings

    var errorDescription: String? {
        switch self {
        case .holdingsUnavailable:
            "该投资者暂无可核验的公开持仓披露"
        case .informationUnavailable:
            "未读取到可用的基金持仓报告"
        case .insufficientFilings:
            "公开持仓报告不足两期，暂时无法计算变化"
        }
    }
}

struct InvestorPortfolioService {
    func fetchBasePortfolio(
        for investor: InvestorPreset,
        cachedTickers: [String: String]
    ) async throws -> PortfolioRefreshContext {
        if investor.holdingsKind == .chineseFund {
            return try await ChinaFundHoldingsClient().fetchBasePortfolio(
                for: investor,
                cachedTickers: cachedTickers
            )
        }
        guard investor.holdingsKind == .sec13F else {
            throw InvestorHoldingsError.holdingsUnavailable
        }
        let history = try await SEC13FClient().holdingsHistory(cik: investor.cik, limit: 20)
        guard var portfolio = PortfolioAnalytics.basePortfolio(
            investor: investor,
            history: history,
            cachedTickers: cachedTickers
        ) else {
            throw SECError.informationTableMissing
        }

        let missingCUSIPs = portfolio.positions
            .filter { $0.putCall == nil && $0.ticker == nil }
            .map(\.cusip)
            + portfolio.changes
                .filter { $0.putCall == nil && $0.ticker == nil }
                .map(\.cusip)
        if !missingCUSIPs.isEmpty,
           let mapped = try? await OpenFIGIClient().mapCUSIPs(missingCUSIPs) {
            for index in portfolio.positions.indices {
                if let ticker = mapped[portfolio.positions[index].cusip] {
                    portfolio.positions[index].ticker = ticker
                }
            }
            for index in portfolio.changes.indices {
                if let ticker = mapped[portfolio.changes[index].cusip] {
                    portfolio.changes[index].ticker = ticker
                }
            }
        }

        return PortfolioRefreshContext(portfolio: portfolio, history: history)
    }
}

struct OpenFIGIClient {
    func mapCUSIPs(_ cusips: [String]) async throws -> [String: String] {
        let unique = Array(Set(cusips.map { $0.uppercased() })).sorted()
        var mappings: [String: String] = [:]

        for (index, chunk) in unique.chunked(into: 5).enumerated() {
            if index > 0 {
                try await Task.sleep(for: .seconds(2.5))
            }
            var request = URLRequest(url: URL(string: "https://api.openfigi.com/v3/mapping")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 25
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                chunk.map {
                    OpenFIGIJob(
                        idType: "ID_CUSIP",
                        idValue: $0,
                        marketSecDes: "Equity"
                    )
                }
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw FeedError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else { throw FeedError.http(http.statusCode) }
            let results = try JSONDecoder().decode([OpenFIGIMapResponse].self, from: data)

            for (cusip, result) in zip(chunk, results) {
                guard let match = preferredMatch(result.data ?? []),
                      let ticker = match.ticker, !ticker.isEmpty else {
                    continue
                }
                mappings[cusip] = normalizedTicker(ticker)
            }
        }
        return mappings
    }

    private func preferredMatch(_ candidates: [OpenFIGIMatch]) -> OpenFIGIMatch? {
        candidates.first {
            $0.exchCode == "US" &&
                $0.marketSector == "Equity" &&
                $0.securityType2 != "Option"
        } ?? candidates.first {
            $0.marketSector == "Equity" && $0.securityType2 != "Option"
        }
    }

    private func normalizedTicker(_ ticker: String) -> String {
        ticker
            .replacingOccurrences(of: "/", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ChineseSecurityNameClient {
    func names(for symbols: [String]) async throws -> [String: String] {
        let requested = Array(
            Set(
                symbols
                    .map { $0.uppercased() }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
        guard !requested.isEmpty else { return [:] }

        var names = Self.fallbackNames.filter { requested.contains($0.key) }
        for chunk in requested.chunked(into: 30) {
            var components = URLComponents(
                string: "https://push2delay.eastmoney.com/api/qt/ulist.np/get"
            )!
            let securityIDs = chunk.flatMap { symbol in
                [105, 106, 107].map { "\($0).\(symbol)" }
            }
            components.queryItems = [
                URLQueryItem(name: "secids", value: securityIDs.joined(separator: ",")),
                URLQueryItem(name: "fields", value: "f12,f13,f14")
            ]

            var request = URLRequest(url: components.url!)
            request.timeoutInterval = 20
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw FeedError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                throw FeedError.http(http.statusCode)
            }
            names.merge(try Self.parse(data: data)) { current, _ in current }
        }
        return names
    }

    static func parse(data: Data) throws -> [String: String] {
        let response = try JSONDecoder().decode(EastMoneyNameResponse.self, from: data)
        return Dictionary(
            (response.data?.diff ?? []).compactMap { item in
                guard let symbol = item.f12?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let name = item.f14?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !symbol.isEmpty,
                      !name.isEmpty,
                      name != "-",
                      name.range(of: #"\p{Han}"#, options: .regularExpression) != nil else {
                    return nil
                }
                return (symbol.uppercased(), name)
            },
            uniquingKeysWith: { current, _ in current }
        )
    }

    private static let fallbackNames = [
        "BRK.B": "伯克希尔-哈撒韦B",
        "LEN.B": "莱纳B"
    ]
}

struct TwelveDataClient {
    func validate(apiKey: String) async throws {
        let result = try await monthlyPrices(symbols: ["AAPL"], apiKey: apiKey, startDate: nil)
        guard result["AAPL"]?.isEmpty == false else {
            throw TwelveDataError.message("Twelve Data 未返回 AAPL 行情")
        }
    }

    func monthlyPrices(
        symbols: [String],
        apiKey: String,
        startDate: Date? = Calendar.current.date(byAdding: .year, value: -11, to: Date())
    ) async throws -> [String: [MarketPricePoint]] {
        guard !symbols.isEmpty else { return [:] }
        var components = URLComponents(string: "https://api.twelvedata.com/time_series")!
        var queryItems = [
            URLQueryItem(name: "symbol", value: symbols.joined(separator: ",")),
            URLQueryItem(name: "interval", value: "1month"),
            URLQueryItem(name: "adjust", value: "splits"),
            URLQueryItem(name: "order", value: "asc")
        ]
        if let startDate {
            queryItems.append(
                URLQueryItem(name: "start_date", value: Self.requestDateFormatter.string(from: startDate))
            )
        } else {
            queryItems.append(URLQueryItem(name: "outputsize", value: "1"))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        request.setValue("apikey \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FeedError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let error = try? JSONDecoder().decode(TwelveDataAPIError.self, from: data) {
                throw TwelveDataError.message(error.message)
            }
            throw FeedError.http(http.statusCode)
        }
        return try Self.parseTimeSeries(data: data, requestedSymbols: symbols)
    }

    static func parseTimeSeries(
        data: Data,
        requestedSymbols: [String]
    ) throws -> [String: [MarketPricePoint]] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw FeedError.invalidResponse
        }
        if dictionary["status"] as? String == "error" {
            throw TwelveDataError.message(
                dictionary["message"] as? String ?? "Twelve Data 请求失败"
            )
        }

        if dictionary["values"] != nil {
            guard let symbol = requestedSymbols.first else { return [:] }
            return [symbol: try decodeSeries(dictionary)]
        }

        var result: [String: [MarketPricePoint]] = [:]
        for symbol in requestedSymbols {
            guard let raw = dictionary[symbol] as? [String: Any] else { continue }
            if let series = try? decodeSeries(raw) {
                result[symbol] = series
            }
        }
        return result
    }

    private static func decodeSeries(_ object: [String: Any]) throws -> [MarketPricePoint] {
        let data = try JSONSerialization.data(withJSONObject: object)
        let series = try JSONDecoder().decode(TwelveDataSeries.self, from: data)
        if series.status == "error" {
            throw TwelveDataError.message(series.message ?? "Twelve Data 请求失败")
        }
        return (series.values ?? []).compactMap { value in
            guard let date = marketDate(value.datetime),
                  let close = Double(value.close), close > 0 else {
                return nil
            }
            return MarketPricePoint(date: date, close: close)
        }
        .sorted { $0.date < $1.date }
    }

    private static func marketDate(_ value: String) -> Date? {
        marketDateTimeFormatter.date(from: value) ?? requestDateFormatter.date(from: value)
    }

    private static let requestDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let marketDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

@MainActor
final class InvestorHoldingsStore: ObservableObject {
    static let portfolioCacheValidity: TimeInterval = 30 * 24 * 60 * 60

    @Published private(set) var portfolios: [String: InvestorPortfolio] = [:]
    @Published private(set) var refreshingInvestorID: String?
    @Published private(set) var isRefreshingAll = false
    @Published private(set) var completedMarketSymbols = 0
    @Published private(set) var totalMarketSymbols = 0
    @Published var statusMessage: String?
    @Published private(set) var statusInvestorID: String?

    private let stateURL: URL
    private let portfolioService = InvestorPortfolioService()
    private let chineseNameClient = ChineseSecurityNameClient()
    private let marketClient = TwelveDataClient()
    private var localizingInvestorIDs: Set<String> = []

    init(stateURL: URL? = nil) {
        self.stateURL = stateURL ?? Self.defaultStateURL
        load()
    }

    func portfolio(for investorID: String) -> InvestorPortfolio? {
        portfolios[investorID]
    }

    static func isPortfolioCacheFresh(refreshedAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(refreshedAt) < portfolioCacheValidity
    }

    func refreshIfStale(_ investor: InvestorPreset, now: Date = Date()) async {
        guard let portfolio = portfolios[investor.id],
              Self.isPortfolioCacheFresh(refreshedAt: portfolio.refreshedAt, now: now) else {
            await refresh(investor)
            return
        }
        statusInvestorID = investor.id
        statusMessage = "已使用缓存持仓 · 更新于 \(portfolio.refreshedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    func refresh(_ investor: InvestorPreset, includeMarketData: Bool = true) async {
        guard refreshingInvestorID == nil else { return }
        refreshingInvestorID = investor.id
        completedMarketSymbols = 0
        totalMarketSymbols = 0
        statusInvestorID = investor.id
        statusMessage = "正在读取 \(investor.firm) 的 SEC 13F…"
        defer { refreshingInvestorID = nil }

        do {
            let cachedPositions = portfolios.values.flatMap(\.positions)
            let cachedTickers = Dictionary(
                cachedPositions.compactMap { position in
                    position.ticker.map { (position.cusip, $0) }
                },
                uniquingKeysWith: { current, _ in current }
            )
            let context = try await portfolioService.fetchBasePortfolio(
                for: investor,
                cachedTickers: cachedTickers
            )
            var portfolio = mergeCachedMetrics(
                into: context.portfolio,
                cached: portfolios[investor.id]
            )
            let chineseNames = await fetchChineseNames(for: portfolio)
            applyChineseNames(chineseNames, to: &portfolio)
            portfolios[investor.id] = portfolio
            save()

            guard investor.holdingsKind == .sec13F,
                  includeMarketData,
                  let apiKey = KeychainStore.twelveDataAPIKey,
                  !apiKey.isEmpty else {
                statusMessage = investor.holdingsKind == .chineseFund
                    ? "基金季报持仓已更新；仅公开前十大持仓，暂不计算个股行情收益"
                    : "13F 已更新；在设置中添加免费 Twelve Data Key 后可计算成本与收益"
                return
            }

            let symbols = Array(
                Set(
                    portfolio.positions.compactMap { position -> String? in
                        guard position.putCall == nil else { return nil }
                        return position.ticker
                    }
                )
            )
            .sorted()
            totalMarketSymbols = symbols.count

            for (batchIndex, batch) in symbols.chunked(into: 8).enumerated() {
                if batchIndex > 0 {
                    statusMessage = "等待免费行情额度重置 · \(completedMarketSymbols)/\(totalMarketSymbols)"
                    try await Task.sleep(for: .seconds(61))
                }
                statusMessage = "正在补全行情 · \(completedMarketSymbols)/\(totalMarketSymbols)"
                let pricesByTicker = try await marketClient.monthlyPrices(
                    symbols: batch,
                    apiKey: apiKey
                )
                enrich(
                    portfolio: &portfolio,
                    pricesByTicker: pricesByTicker,
                    history: context.history
                )
                completedMarketSymbols += batch.count
                portfolio.refreshedAt = Date()
                portfolios[investor.id] = portfolio
                save()
            }
            statusMessage = "持仓与行情已更新 · \(portfolio.reportDate)"
        } catch is CancellationError {
            statusMessage = "已停止刷新"
        } catch {
            statusMessage = "刷新失败：\(error.localizedDescription)"
        }
    }

    func refreshAll(
        _ investors: [InvestorPreset] = InvestorPreset.featured
    ) async {
        guard refreshingInvestorID == nil, !isRefreshingAll else { return }
        isRefreshingAll = true
        defer { isRefreshingAll = false }
        statusInvestorID = nil
        statusMessage = "正在刷新全部投资者的 SEC 13F…"

        var refreshedCount = 0
        for investor in investors {
            await refresh(investor, includeMarketData: false)
            if portfolios[investor.id] != nil {
                refreshedCount += 1
            }
        }
        statusInvestorID = nil
        statusMessage = "已刷新 \(refreshedCount) 位投资者的 13F 持仓"
    }

    func refreshAllIfStale(
        _ investors: [InvestorPreset] = InvestorPreset.featured,
        now: Date = Date()
    ) async {
        let staleInvestors = investors.filter { investor in
            guard let portfolio = portfolios[investor.id] else { return true }
            return !Self.isPortfolioCacheFresh(refreshedAt: portfolio.refreshedAt, now: now)
        }
        guard !staleInvestors.isEmpty else {
            statusMessage = "已使用全部持仓缓存 · 更新于最近 30 天内"
            return
        }
        await refreshAll(staleInvestors)
    }

    func loadChineseNames(for investorID: String) async {
        guard localizingInvestorIDs.insert(investorID).inserted,
              let portfolio = portfolios[investorID] else {
            return
        }
        defer { localizingInvestorIDs.remove(investorID) }

        let names = await fetchChineseNames(for: portfolio)
        guard !names.isEmpty,
              var current = portfolios[investorID] else {
            return
        }
        applyChineseNames(names, to: &current)
        portfolios[investorID] = current
        save()
    }

    private func fetchChineseNames(for portfolio: InvestorPortfolio) async -> [String: String] {
        let positionSymbols = portfolio.positions.compactMap { position -> String? in
            guard position.chineseName == nil,
                  position.putCall == nil else {
                return nil
            }
            return position.ticker
        }
        let changeSymbols = portfolio.changes.compactMap { change -> String? in
            guard change.localizedName == nil,
                  change.putCall == nil else {
                return nil
            }
            return change.ticker
        }
        return (try? await chineseNameClient.names(for: Array(Set(positionSymbols + changeSymbols)).sorted())) ?? [:]
    }

    private func applyChineseNames(
        _ names: [String: String],
        to portfolio: inout InvestorPortfolio
    ) {
        for index in portfolio.positions.indices {
            guard let ticker = portfolio.positions[index].ticker?.uppercased(),
                  let name = names[ticker] else {
                continue
            }
            portfolio.positions[index].localizedName = name
        }
        for index in portfolio.changes.indices {
            guard let ticker = portfolio.changes[index].ticker?.uppercased(),
                  let name = names[ticker] else {
                continue
            }
            portfolio.changes[index].localizedName = name
        }
    }

    private func enrich(
        portfolio: inout InvestorPortfolio,
        pricesByTicker: [String: [MarketPricePoint]],
        history: [ReportedPortfolio]
    ) {
        for index in portfolio.positions.indices {
            guard let ticker = portfolio.positions[index].ticker,
                  let prices = pricesByTicker[ticker],
                  let latest = prices.last else {
                continue
            }
            let estimate = PortfolioAnalytics.estimatedCost(
                for: portfolio.positions[index].securityKey,
                history: history,
                prices: prices
            )
            portfolio.positions[index].latestPrice = latest.close
            portfolio.positions[index].estimatedCost = estimate?.price
            portfolio.positions[index].estimatedProfitLoss = estimate.map {
                latest.close / $0.price - 1
            }
            portfolio.positions[index].costConfidence = estimate?.confidence
            portfolio.positions[index].returns = PortfolioAnalytics.annualizedReturns(prices: prices)
            portfolio.positions[index].marketDataAsOf = latest.date
        }
    }

    private func mergeCachedMetrics(
        into portfolio: InvestorPortfolio,
        cached: InvestorPortfolio?
    ) -> InvestorPortfolio {
        guard let cached else { return portfolio }
        let cachedByKey = Dictionary(uniqueKeysWithValues: cached.positions.map { ($0.securityKey, $0) })
        var merged = portfolio
        for index in merged.positions.indices {
            guard let prior = cachedByKey[merged.positions[index].securityKey] else { continue }
            merged.positions[index].ticker = merged.positions[index].ticker ?? prior.ticker
            merged.positions[index].localizedName =
                merged.positions[index].localizedName ?? prior.localizedName
            merged.positions[index].latestPrice = prior.latestPrice
            merged.positions[index].estimatedCost = prior.estimatedCost
            merged.positions[index].estimatedProfitLoss = prior.estimatedProfitLoss
            merged.positions[index].costConfidence = prior.costConfidence
            merged.positions[index].returns = prior.returns
            merged.positions[index].marketDataAsOf = prior.marketDataAsOf
        }
        let cachedChangesByKey = Dictionary(uniqueKeysWithValues: cached.changes.map { ($0.securityKey, $0) })
        for index in merged.changes.indices {
            guard let prior = cachedChangesByKey[merged.changes[index].securityKey] else { continue }
            merged.changes[index].ticker = merged.changes[index].ticker ?? prior.ticker
            merged.changes[index].localizedName =
                merged.changes[index].localizedName ?? prior.localizedName
        }
        return merged
    }

    private func load() {
        do {
            let data = try Data(contentsOf: stateURL)
            let cache = try JSONDecoder.investorHoldings.decode(InvestorPortfolioCache.self, from: data)
            portfolios = Dictionary(uniqueKeysWithValues: cache.portfolios.map { ($0.investorID, $0) })
        } catch {
            portfolios = [:]
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: stateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let cache = InvestorPortfolioCache(
                portfolios: portfolios.values.sorted { $0.investorID < $1.investorID }
            )
            let data = try JSONEncoder.investorHoldings.encode(cache)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            statusMessage = "持仓缓存保存失败：\(error.localizedDescription)"
        }
    }

    private static var defaultStateURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "SignalDesk", directoryHint: .isDirectory)
            .appending(path: "investor-portfolios.json")
    }
}

private struct InvestorPortfolioCache: Codable {
    var portfolios: [InvestorPortfolio]
}

private struct OpenFIGIJob: Encodable {
    var idType: String
    var idValue: String
    var marketSecDes: String
}

private struct OpenFIGIMapResponse: Decodable {
    var data: [OpenFIGIMatch]?
}

private struct OpenFIGIMatch: Decodable {
    var ticker: String?
    var exchCode: String?
    var marketSector: String?
    var securityType2: String?
}

private struct EastMoneyNameResponse: Decodable {
    var data: EastMoneyNameData?
}

private struct EastMoneyNameData: Decodable {
    var diff: [EastMoneyNameItem]?
}

private struct EastMoneyNameItem: Decodable {
    var f12: String?
    var f14: String?
}

private struct TwelveDataSeries: Decodable {
    var values: [TwelveDataValue]?
    var status: String?
    var message: String?
}

private struct TwelveDataValue: Decodable {
    var datetime: String
    var close: String
}

private struct TwelveDataAPIError: Decodable {
    var message: String
}

enum TwelveDataError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): message
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

private extension JSONEncoder {
    static var investorHoldings: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var investorHoldings: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
