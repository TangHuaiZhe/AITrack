import Foundation

struct Holding: Equatable {
    var issuer: String
    var titleOfClass: String
    var cusip: String
    var valueUSD: Int64
    var shares: Double
    var putCall: String?

    var key: String {
        "\(cusip)|\(titleOfClass)|\(putCall ?? "")"
    }
}

struct ReportedPortfolio: Equatable {
    var reportDate: String
    var filingDate: String
    var holdings: [Holding]
}

enum HoldingChangeKind: String {
    case added
    case exited
    case increased
    case decreased

    var title: String {
        switch self {
        case .added: "新增"
        case .exited: "清仓"
        case .increased: "增持"
        case .decreased: "减持"
        }
    }
}

struct HoldingChange: Equatable {
    var kind: HoldingChangeKind
    var holding: Holding
    var oldShares: Double
    var newShares: Double
    var oldValueUSD: Int64
    var newValueUSD: Int64

    var shareChangePercent: Double? {
        guard oldShares > 0 else { return nil }
        return (newShares - oldShares) / oldShares
    }

    var valueDelta: Int64 { newValueUSD - oldValueUSD }
}

enum HoldingsDiffer {
    static func changes(old: [Holding], new: [Holding]) -> [HoldingChange] {
        let oldMap = aggregated(old)
        let newMap = aggregated(new)
        let keys = Set(oldMap.keys).union(newMap.keys)

        return keys.compactMap { key in
            switch (oldMap[key], newMap[key]) {
            case (nil, let current?):
                return HoldingChange(
                    kind: .added,
                    holding: current,
                    oldShares: 0,
                    newShares: current.shares,
                    oldValueUSD: 0,
                    newValueUSD: current.valueUSD
                )
            case (let previous?, nil):
                return HoldingChange(
                    kind: .exited,
                    holding: previous,
                    oldShares: previous.shares,
                    newShares: 0,
                    oldValueUSD: previous.valueUSD,
                    newValueUSD: 0
                )
            case (let previous?, let current?):
                guard previous.shares != current.shares else { return nil }
                return HoldingChange(
                    kind: current.shares > previous.shares ? .increased : .decreased,
                    holding: current,
                    oldShares: previous.shares,
                    newShares: current.shares,
                    oldValueUSD: previous.valueUSD,
                    newValueUSD: current.valueUSD
                )
            default:
                return nil
            }
        }
    }

    private static func aggregated(_ holdings: [Holding]) -> [String: Holding] {
        holdings.reduce(into: [:]) { result, holding in
            if result[holding.key] == nil {
                result[holding.key] = holding
            } else {
                result[holding.key]?.shares += holding.shares
                result[holding.key]?.valueUSD += holding.valueUSD
            }
        }
    }
}

struct SEC13FClient {
    private let userAgent = "TrackAI/0.7 tanghuaizhe@me.com"

    func fetch(_ source: TrackedSource) async throws -> [SignalEvent] {
        guard let cik = cik(from: source.feedURL) else { throw FeedError.invalidURL }
        let filings = try await recentFilings(cik: cik, limit: 2)
        guard filings.count >= 2 else {
            throw SECError.insufficientFilings
        }

        let current = filings[0]
        let previous = filings[1]
        async let currentHoldings = holdings(cik: cik, filing: current)
        async let previousHoldings = holdings(cik: cik, filing: previous)
        let changes = HoldingsDiffer.changes(
            old: try await previousHoldings,
            new: try await currentHoldings
        )
        .filter { change in
            guard let percent = change.shareChangePercent else { return true }
            return abs(percent) >= 0.05
        }
        .sorted { abs($0.valueDelta) > abs($1.valueDelta) }

        return makeEvents(
            changes: changes,
            source: source,
            cik: cik,
            filing: current,
            previousReportDate: previous.reportDate
        )
    }

    func holdingsHistory(cik: String, limit: Int = 20) async throws -> [ReportedPortfolio] {
        let filings = try await recentFilings(cik: cik, limit: limit)
        guard !filings.isEmpty else { throw SECError.insufficientFilings }

        var history: [ReportedPortfolio] = []
        for filing in filings {
            history.append(
                ReportedPortfolio(
                    reportDate: filing.reportDate,
                    filingDate: filing.filingDate,
                    holdings: try await holdings(cik: cik, filing: filing)
                )
            )
        }
        return history
    }

    private func recentFilings(cik: String, limit: Int) async throws -> [SECFiling] {
        let paddedCIK = String(repeating: "0", count: max(0, 10 - cik.count)) + cik
        let url = URL(string: "https://data.sec.gov/submissions/CIK\(paddedCIK).json")!
        let data = try await request(url)
        let response = try JSONDecoder().decode(SECSubmissions.self, from: data)
        let recent = response.filings.recent
        let count = [
            recent.form.count,
            recent.accessionNumber.count,
            recent.filingDate.count,
            recent.reportDate.count,
            recent.primaryDocument.count
        ].min() ?? 0

        var filings: [SECFiling] = []
        var seenReportDates = Set<String>()
        for index in 0..<count where recent.form[index] == "13F-HR" {
            let reportDate = recent.reportDate[index]
            guard seenReportDates.insert(reportDate).inserted else { continue }
            filings.append(
                SECFiling(
                    accession: recent.accessionNumber[index],
                    filingDate: recent.filingDate[index],
                    reportDate: reportDate,
                    primaryDocument: recent.primaryDocument[index]
                )
            )
            if filings.count == limit { break }
        }
        return filings
    }

    private func holdings(cik: String, filing: SECFiling) async throws -> [Holding] {
        let accession = filing.accession.replacingOccurrences(of: "-", with: "")
        let base = "https://www.sec.gov/Archives/edgar/data/\(cik)/\(accession)"
        let indexData = try await request(URL(string: "\(base)/index.json")!)
        let index = try JSONDecoder().decode(SECArchiveIndex.self, from: indexData)
        let primaryName = filing.primaryDocument.split(separator: "/").last.map(String.init) ?? filing.primaryDocument
        let candidates = index.directory.item
            .map(\.name)
            .filter { $0.lowercased().hasSuffix(".xml") && $0 != primaryName }
            .sorted { lhs, rhs in
                let leftLooksRelevant = lhs.lowercased().contains("info")
                let rightLooksRelevant = rhs.lowercased().contains("info")
                return leftLooksRelevant && !rightLooksRelevant
            }

        for name in candidates {
            let data = try await request(URL(string: "\(base)/\(name)")!)
            let valueMultiplier: Int64 = filing.filingDate >= "2023-01-03" ? 1 : 1_000
            if let parsed = try? SEC13FXMLParser.parse(
                data: data,
                valueMultiplier: valueMultiplier
            ),
            !parsed.isEmpty {
                return parsed
            }
        }
        throw SECError.informationTableMissing
    }

    private func request(_ url: URL) async throws -> Data {
        try await Task.sleep(for: .milliseconds(120))
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, application/xml, text/xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FeedError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw FeedError.http(http.statusCode) }
        return data
    }

    private func cik(from urlString: String) -> String? {
        guard let components = URLComponents(string: urlString),
              let raw = components.queryItems?.first(where: { $0.name.uppercased() == "CIK" })?.value else {
            return nil
        }
        let digits = raw.filter(\.isNumber).drop(while: { $0 == "0" })
        return digits.isEmpty ? nil : String(digits)
    }

    private func makeEvents(
        changes: [HoldingChange],
        source: TrackedSource,
        cik: String,
        filing: SECFiling,
        previousReportDate: String
    ) -> [SignalEvent] {
        let date = SECDateParser.date(filing.filingDate) ?? Date()
        let accession = filing.accession.replacingOccurrences(of: "-", with: "")
        let url = "https://www.sec.gov/Archives/edgar/data/\(cik)/\(accession)/\(filing.accession)-index.html"
        let counts = Dictionary(grouping: changes, by: \.kind).mapValues(\.count)
        let summary = "对比 \(previousReportDate)：新增 \(counts[.added, default: 0])、清仓 \(counts[.exited, default: 0])、增持 \(counts[.increased, default: 0])、减持 \(counts[.decreased, default: 0])。共识别 \(changes.count) 项显著变化。"

        var events = [
            SignalEvent(
                id: "\(source.id.uuidString)|13f|\(filing.accession)",
                sourceID: source.id,
                sourceName: source.name,
                title: "13F 持仓变化 · \(filing.reportDate)",
                summary: summary,
                url: url,
                publishedAt: date,
                category: .holding,
                importance: 94,
                matchedTopics: ["13F", "持仓"],
                domains: [.investmentBusiness]
            )
        ]
        events += changes.prefix(80).map { change in
            SignalEvent(
                id: "\(source.id.uuidString)|13f|\(filing.accession)|\(change.holding.key)",
                sourceID: source.id,
                sourceName: source.name,
                title: "\(change.kind.title) · \(change.holding.issuer)",
                summary: changeSummary(change),
                url: url,
                publishedAt: date,
                category: .holding,
                importance: importance(change),
                matchedTopics: ["13F", "持仓", change.kind.title],
                domains: [.investmentBusiness]
            )
        }
        return events
    }

    private func changeSummary(_ change: HoldingChange) -> String {
        let shares = "\(Self.number(change.oldShares)) → \(Self.number(change.newShares)) 股"
        let values = "\(Self.currency(change.oldValueUSD)) → \(Self.currency(change.newValueUSD))"
        if let percent = change.shareChangePercent {
            let percentText = String(format: "%+.1f%%", percent * 100)
            return "\(shares)（\(percentText)） · 申报价值 \(values) · CUSIP \(change.holding.cusip)"
        }
        return "\(shares) · 申报价值 \(values) · CUSIP \(change.holding.cusip)"
    }

    private func importance(_ change: HoldingChange) -> Int {
        let base = change.kind == .added || change.kind == .exited ? 84 : 76
        let magnitude = abs(change.valueDelta)
        if magnitude >= 1_000_000_000 { return min(base + 12, 100) }
        if magnitude >= 100_000_000 { return min(base + 8, 100) }
        if magnitude >= 10_000_000 { return min(base + 4, 100) }
        return base
    }

    private static func number(_ value: Double) -> String {
        compact(value, prefix: "")
    }

    private static func currency(_ value: Int64) -> String {
        compact(Double(value), prefix: "$")
    }

    private static func compact(_ value: Double, prefix: String) -> String {
        let magnitude = abs(value)
        let scaled: Double
        let suffix: String
        if magnitude >= 1_000_000_000 {
            scaled = value / 1_000_000_000
            suffix = "B"
        } else if magnitude >= 1_000_000 {
            scaled = value / 1_000_000
            suffix = "M"
        } else if magnitude >= 1_000 {
            scaled = value / 1_000
            suffix = "K"
        } else {
            return "\(prefix)\(Int(value.rounded()))"
        }
        return "\(prefix)\(String(format: "%.1f", scaled))\(suffix)"
    }
}

enum SECError: LocalizedError {
    case insufficientFilings
    case informationTableMissing

    var errorDescription: String? {
        switch self {
        case .insufficientFilings: "该 CIK 找不到两个可比较的 13F-HR 报告期"
        case .informationTableMissing: "申报中未找到可解析的 13F information table"
        }
    }
}

enum SEC13FXMLParser {
    static func parse(data: Data, valueMultiplier: Int64 = 1) throws -> [Holding] {
        let delegate = SEC13FXMLDelegate(valueMultiplier: valueMultiplier)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), !delegate.holdings.isEmpty else {
            throw parser.parserError ?? SECError.informationTableMissing
        }
        return delegate.holdings
    }
}

private final class SEC13FXMLDelegate: NSObject, XMLParserDelegate {
    private let valueMultiplier: Int64
    private var currentText = ""
    private var current: Draft?
    var holdings: [Holding] = []

    init(valueMultiplier: Int64) {
        self.valueMultiplier = valueMultiplier
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentText = ""
        if normalized(elementName) == "infotable" { current = Draft() }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard current != nil else { return }
        let element = normalized(elementName)
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch element {
        case "nameofissuer": current?.issuer = text
        case "titleofclass": current?.titleOfClass = text
        case "cusip": current?.cusip = text
        case "value": current?.reportedValue = Int64(text) ?? 0
        case "sshprnamt": current?.shares = Double(text) ?? 0
        case "putcall": current?.putCall = text.isEmpty ? nil : text
        case "infotable":
            if let current, !current.issuer.isEmpty, !current.cusip.isEmpty {
                holdings.append(
                    Holding(
                        issuer: current.issuer,
                        titleOfClass: current.titleOfClass,
                        cusip: current.cusip,
                        valueUSD: current.reportedValue * valueMultiplier,
                        shares: current.shares,
                        putCall: current.putCall
                    )
                )
            }
            self.current = nil
        default: break
        }
        currentText = ""
    }

    private func normalized(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init)?.lowercased() ?? name.lowercased()
    }

    private struct Draft {
        var issuer = ""
        var titleOfClass = ""
        var cusip = ""
        var reportedValue: Int64 = 0
        var shares: Double = 0
        var putCall: String?
    }
}

private struct SECFiling {
    var accession: String
    var filingDate: String
    var reportDate: String
    var primaryDocument: String
}

private struct SECSubmissions: Decodable {
    var filings: Filings
    struct Filings: Decodable {
        var recent: Recent
    }
    struct Recent: Decodable {
        var accessionNumber: [String]
        var filingDate: [String]
        var reportDate: [String]
        var form: [String]
        var primaryDocument: [String]
    }
}

private struct SECArchiveIndex: Decodable {
    var directory: Directory
    struct Directory: Decodable {
        var item: [Item]
    }
    struct Item: Decodable {
        var name: String
    }
}

enum SECDateParser {
    static func date(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
}
