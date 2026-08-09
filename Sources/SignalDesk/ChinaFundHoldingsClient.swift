import Foundation

struct ChinaFundHoldingsClient {
    func fetchBasePortfolio(
        for investor: InvestorPreset,
        cachedTickers: [String: String]
    ) async throws -> PortfolioRefreshContext {
        guard !investor.fundCodes.isEmpty else {
            throw InvestorHoldingsError.holdingsUnavailable
        }

        var fundReports: [[ChinaFundQuarter]] = []
        for fundCode in investor.fundCodes {
            let data = try await fetch(fundCode: fundCode)
            let reports = try Self.parse(data: data)
            guard !reports.isEmpty else { continue }
            fundReports.append(reports)
        }

        guard !fundReports.isEmpty else {
            throw InvestorHoldingsError.informationUnavailable
        }

        let dateSets = fundReports.map { Set($0.map(\.reportDate)) }
        let commonDates = dateSets.dropFirst().reduce(dateSets[0]) { $0.intersection($1) }
        let dates = (commonDates.count >= 2 ? commonDates : Set(fundReports.flatMap { $0.map(\.reportDate) }))
            .sorted(by: >)
        guard let latestDate = dates.first else {
            throw InvestorHoldingsError.informationUnavailable
        }

        let latestReports = fundReports.flatMap { reports in
            reports.filter { $0.reportDate == latestDate }
        }
        let previousReports = dates.dropFirst().first.map { previousDate in
            fundReports.flatMap { reports in
                reports.filter { $0.reportDate == previousDate }
            }
        } ?? []
        let history = dates.prefix(20).map { date in
            ReportedPortfolio(
                reportDate: date,
                filingDate: date,
                holdings: Self.aggregate(
                    fundReports.flatMap { reports in
                        reports.first { $0.reportDate == date }?.holdings ?? []
                    }
                )
            )
        }

        guard !latestReports.isEmpty, !previousReports.isEmpty else {
            throw InvestorHoldingsError.insufficientFilings
        }

        let tickerMap = latestReports
            .flatMap(\.holdings)
            .reduce(into: cachedTickers) { result, holding in
                result[holding.cusip] = Self.ticker(for: holding.cusip)
            }
        guard var portfolio = PortfolioAnalytics.basePortfolio(
            investor: investor,
            history: history,
            cachedTickers: tickerMap
        ) else {
            throw InvestorHoldingsError.informationUnavailable
        }
        portfolio.currencyCode = "CNY"
        for index in portfolio.positions.indices {
            portfolio.positions[index].localizedName = portfolio.positions[index].issuer
        }
        for index in portfolio.changes.indices {
            portfolio.changes[index].ticker = tickerMap[portfolio.changes[index].cusip]
            portfolio.changes[index].localizedName = portfolio.changes[index].issuer
        }
        return PortfolioRefreshContext(portfolio: portfolio, history: history)
    }

    private func fetch(fundCode: String) async throws -> Data {
        var components = URLComponents(
            string: "https://fundf10.eastmoney.com/FundArchivesDatas.aspx"
        )!
        components.queryItems = [
            URLQueryItem(name: "type", value: "jjcc"),
            URLQueryItem(name: "code", value: fundCode),
            URLQueryItem(name: "topline", value: "10"),
            URLQueryItem(name: "year", value: ""),
            URLQueryItem(name: "month", value: ""),
            URLQueryItem(name: "rt", value: String(Date().timeIntervalSince1970))
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://fund.eastmoney.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FeedError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FeedError.http(http.statusCode)
        }
        return data
    }

    static func parse(data: Data) throws -> [ChinaFundQuarter] {
        guard let raw = String(data: data, encoding: .utf8) else {
            throw FeedError.invalidResponse
        }
        guard let content = firstCapture(
            pattern: #"content:\"(.*)\",arryear:"#,
            in: raw
        ) else {
            return []
        }

        return content
            .components(separatedBy: "<div class='boxitem")
            .dropFirst()
            .compactMap { block in
            guard let date = firstCapture(
                pattern: #"截止至：<font[^>]*>(\d{4}-\d{2}-\d{2})</font>"#,
                in: block
            ),
            let body = firstCapture(pattern: #"<tbody>(.*?)</tbody>"#, in: block) else {
                return nil
            }
            let rows = allCaptures(pattern: #"<tr>(.*?)</tr>"#, in: body)
            let holdings = rows.compactMap(parseHoldingRow)
            guard !holdings.isEmpty else { return nil }
            return ChinaFundQuarter(reportDate: date, holdings: holdings)
            }
    }

    private static func parseHoldingRow(_ captures: [String]) -> Holding? {
        guard let row = captures.first else { return nil }
        let cells = allCaptures(pattern: #"<td(?:\s[^>]*)?>(.*?)</td>"#, in: row)
            .map { stripHTML($0.first ?? "") }
        guard cells.count >= 6,
              let codeMatch = firstCaptures(pattern: #"unify/r/(\d+)\.(\d+)"#, in: row),
              codeMatch.count == 2,
              let shares = number(cells[cells.count >= 9 ? 7 : cells.count >= 7 ? 5 : 4]),
              let value = number(cells[cells.count >= 9 ? 8 : cells.count >= 7 ? 6 : 5]) else {
            return nil
        }
        let market = codeMatch[0]
        let code = codeMatch[1]
        let cusip = "\(market).\(code)"
        return Holding(
            issuer: cells[2],
            titleOfClass: "FUND_TOP10",
            cusip: cusip,
            valueUSD: Int64((value * 10_000).rounded()),
            shares: shares * 10_000,
            putCall: nil
        )
    }

    private static func aggregate(_ holdings: [Holding]) -> [Holding] {
        var result: [String: Holding] = [:]
        for holding in holdings {
            if result[holding.key] == nil {
                result[holding.key] = holding
            } else {
                result[holding.key]?.shares += holding.shares
                result[holding.key]?.valueUSD += holding.valueUSD
            }
        }
        return Array(result.values)
    }

    private static func ticker(for cusip: String) -> String {
        let parts = cusip.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return cusip }
        switch parts[0] {
        case "0": return "SZ\(parts[1])"
        case "1": return "SH\(parts[1])"
        case "116": return "HK\(parts[1])"
        default: return "\(parts[0])\(parts[1])"
        }
    }

    private static func stripHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func number(_ value: String) -> Double? {
        Double(value.replacingOccurrences(of: ",", with: ""))
    }

    private static func firstCapture(pattern: String, in value: String) -> String? {
        firstCaptures(pattern: pattern, in: value)?.first
    }

    private static func firstCaptures(pattern: String, in value: String) -> [String]? {
        allCaptures(pattern: pattern, in: value).first
    }

    private static func allCaptures(pattern: String, in value: String) -> [[String]] {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else { return [] }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: value) else { return nil }
                return String(value[range])
            }
        }
    }
}

struct ChinaFundQuarter {
    var reportDate: String
    var holdings: [Holding]
}
