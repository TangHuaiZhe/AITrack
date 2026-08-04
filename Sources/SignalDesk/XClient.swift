import Foundation
import Security

enum XProvider: String, CaseIterable, Identifiable {
    case twitterAPIIO
    case brightData

    static let defaultsKey = "x-data-provider"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twitterAPIIO: "TwitterAPI.io"
        case .brightData: "Bright Data"
        }
    }

    var detail: String {
        switch self {
        case .twitterAPIIO:
            "按返回的 Post 计费，适合高频增量刷新。"
        case .brightData:
            "按成功返回的记录计费，适合批量刷新；每次请求最多查询 20 个账号。"
        }
    }

    var apiKey: String? {
        switch self {
        case .twitterAPIIO: KeychainStore.twitterAPIIOKey
        case .brightData: KeychainStore.brightDataAPIKey
        }
    }

    var signupURL: URL {
        switch self {
        case .twitterAPIIO: URL(string: "https://twitterapi.io")!
        case .brightData: URL(string: "https://brightdata.com/products/web-scraper/twitter")!
        }
    }

    static var selected: XProvider {
        let raw = UserDefaults.standard.string(forKey: defaultsKey)
        return raw.flatMap(XProvider.init(rawValue:)) ?? .twitterAPIIO
    }
}

enum XError: LocalizedError {
    case missingAPIKey(String)
    case invalidUsername
    case brightDataJobFailed
    case brightDataTimeout
    case invalidBrightDataResponse
    case brightDataCrawler(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider): "尚未在设置中保存 \(provider) API Key"
        case .invalidUsername: "X 用户名无效"
        case .brightDataJobFailed: "Bright Data 抓取任务失败"
        case .brightDataTimeout: "Bright Data 抓取时间过长，请稍后重试"
        case .invalidBrightDataResponse: "Bright Data 返回了无法识别的响应"
        case .brightDataCrawler(let message): "Bright Data 抓取失败：\(message)"
        }
    }
}

struct XClient {
    private static let brightDataBatchSize = 20
    private static let brightDataDatasetID = "gd_lwxkxvnf1cynvib9co"

    var provider: XProvider = .selected

    func fetch(_ source: TrackedSource) async throws -> [SignalEvent] {
        let result = try await fetch([source])
        return result[source.id] ?? []
    }

    func fetch(_ sources: [TrackedSource]) async throws -> [UUID: [SignalEvent]] {
        switch provider {
        case .twitterAPIIO:
            var result: [UUID: [SignalEvent]] = [:]
            for source in sources {
                result[source.id] = try await fetchTwitterAPIIO(source)
            }
            return result
        case .brightData:
            return try await fetchBrightData(sources)
        }
    }

    func events(
        from data: Data,
        username: String,
        source: TrackedSource
    ) throws -> [SignalEvent] {
        let response = try JSONDecoder.xData.decode(TwitterAPIIOResponse.self, from: data)
        return (response.tweets ?? []).map { post in
            event(
                id: post.id,
                text: post.text,
                username: username,
                url: "https://x.com/\(username)/status/\(post.id)",
                publishedAt: post.createdAt ?? Date(),
                metrics: post.metrics,
                providerName: XProvider.twitterAPIIO.title,
                source: source
            )
        }
    }

    func brightDataEvents(
        from data: Data,
        sources: [TrackedSource]
    ) throws -> [UUID: [SignalEvent]] {
        let posts = try JSONDecoder.xData.decode([BrightDataPost].self, from: data)
        let validPosts = posts.filter { $0.id != nil && $0.description != nil }
        if validPosts.isEmpty, let error = posts.compactMap(\.error).first {
            throw XError.brightDataCrawler(error.prefixText(240))
        }
        var result: [UUID: [SignalEvent]] = [:]

        for source in sources {
            let username = try normalizedUsername(for: source)
            let matching = posts
                .filter { post in
                    guard post.userPosted?.caseInsensitiveCompare(username) == .orderedSame,
                          let id = post.id,
                          let text = post.description,
                          !id.isEmpty,
                          !text.isEmpty,
                          !post.isRetweetPost,
                          !post.isReplyPost else {
                        return false
                    }
                    return true
                }
                .sorted { ($0.datePosted ?? .distantPast) > ($1.datePosted ?? .distantPast) }
                .prefix(20)

            result[source.id] = matching.compactMap { post in
                guard let id = post.id,
                      let text = post.description else {
                    return nil
                }
                let metrics = XPost.PublicMetrics(
                    retweetCount: post.reposts ?? 0,
                    replyCount: post.replies ?? 0,
                    likeCount: post.likes ?? 0,
                    quoteCount: post.quotes ?? 0
                )
                return event(
                    id: id,
                    text: text,
                    username: username,
                    url: post.url ?? "https://x.com/\(username)/status/\(id)",
                    publishedAt: post.datePosted ?? Date(),
                    metrics: metrics,
                    providerName: XProvider.brightData.title,
                    source: source
                )
            }
        }
        return result
    }

    func validateAPIKey(_ apiKey: String) async throws {
        switch provider {
        case .twitterAPIIO:
            _ = try await twitterAPIIORequest(
                Self.searchURL(username: "XDevelopers"),
                apiKey: apiKey
            )
        case .brightData:
            var request = URLRequest(
                url: URL(string: "https://api.brightdata.com/datasets/list")!
            )
            request.timeoutInterval = 20
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            _ = try await responseData(for: request)
        }
    }

    static func searchURL(username: String, lastCheckedAt: Date? = nil) -> URL {
        var query = "from:\(username) -filter:replies -filter:retweets"
        if let lastCheckedAt {
            let overlap = lastCheckedAt.addingTimeInterval(-5 * 60)
            query += " since_time:\(Int(overlap.timeIntervalSince1970))"
        }
        var components = URLComponents(
            string: "https://api.twitterapi.io/twitter/tweet/advanced_search"
        )!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "queryType", value: "Latest")
        ]
        return components.url!
    }

    static var brightDataURL: URL {
        var components = URLComponents(
            string: "https://api.brightdata.com/datasets/v3/scrape"
        )!
        components.queryItems = [
            URLQueryItem(name: "dataset_id", value: brightDataDatasetID),
            URLQueryItem(name: "type", value: "discover_new"),
            URLQueryItem(name: "discover_by", value: "profiles_array"),
            URLQueryItem(name: "include_errors", value: "true"),
            URLQueryItem(name: "limit_per_input", value: "20")
        ]
        return components.url!
    }

    static func brightDataRequestBody(usernames: [String]) throws -> Data {
        try JSONEncoder().encode(
            BrightDataRequest(
                input: [.init(urls: usernames.map { "https://x.com/\($0)" })]
            )
        )
    }

    static func brightDataProgressURL(snapshotID: String) -> URL {
        URL(string: "https://api.brightdata.com/datasets/v3/progress/\(snapshotID)")!
    }

    static func brightDataSnapshotURL(snapshotID: String) -> URL {
        var components = URLComponents(
            string: "https://api.brightdata.com/datasets/v3/snapshot/\(snapshotID)"
        )!
        components.queryItems = [URLQueryItem(name: "format", value: "json")]
        return components.url!
    }

    static func brightDataSnapshotID(from data: Data) throws -> String {
        try JSONDecoder.xData.decode(BrightDataSnapshot.self, from: data).snapshotId
    }

    private func fetchTwitterAPIIO(_ source: TrackedSource) async throws -> [SignalEvent] {
        guard let apiKey = KeychainStore.twitterAPIIOKey, !apiKey.isEmpty else {
            throw XError.missingAPIKey(XProvider.twitterAPIIO.title)
        }
        let username = try normalizedUsername(for: source)
        let data = try await twitterAPIIORequest(
            Self.searchURL(username: username, lastCheckedAt: source.lastCheckedAt),
            apiKey: apiKey
        )
        return try events(from: data, username: username, source: source)
    }

    private func fetchBrightData(
        _ sources: [TrackedSource]
    ) async throws -> [UUID: [SignalEvent]] {
        guard let apiKey = KeychainStore.brightDataAPIKey, !apiKey.isEmpty else {
            throw XError.missingAPIKey(XProvider.brightData.title)
        }
        guard !sources.isEmpty else { return [:] }

        var result: [UUID: [SignalEvent]] = [:]
        for start in stride(from: 0, to: sources.count, by: Self.brightDataBatchSize) {
            let end = min(start + Self.brightDataBatchSize, sources.count)
            let batch = Array(sources[start..<end])
            let usernames = try batch.map(normalizedUsername)
            let body = try Self.brightDataRequestBody(usernames: usernames)
            var request = URLRequest(url: Self.brightDataURL)
            request.httpMethod = "POST"
            request.httpBody = body
            request.timeoutInterval = 120
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (initialData, response) = try await response(for: request)
            let data: Data
            if response.statusCode == 202 {
                guard let snapshotID = try? Self.brightDataSnapshotID(from: initialData) else {
                    throw XError.invalidBrightDataResponse
                }
                data = try await waitForBrightDataSnapshot(snapshotID, apiKey: apiKey)
            } else {
                data = initialData
            }
            let batchResult = try brightDataEvents(from: data, sources: batch)
            result.merge(batchResult) { _, new in new }
        }
        return result
    }

    private func waitForBrightDataSnapshot(
        _ snapshotID: String,
        apiKey: String
    ) async throws -> Data {
        for _ in 0..<300 {
            try Task.checkCancellation()
            var progressRequest = URLRequest(
                url: Self.brightDataProgressURL(snapshotID: snapshotID)
            )
            progressRequest.timeoutInterval = 20
            progressRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let progressData = try await responseData(for: progressRequest)
            let progress = try JSONDecoder.xData.decode(
                BrightDataSnapshotProgress.self,
                from: progressData
            )

            switch progress.status.lowercased() {
            case "ready":
                var downloadRequest = URLRequest(
                    url: Self.brightDataSnapshotURL(snapshotID: snapshotID)
                )
                downloadRequest.timeoutInterval = 60
                downloadRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                return try await responseData(for: downloadRequest)
            case "failed":
                throw XError.brightDataJobFailed
            default:
                try await Task.sleep(for: .seconds(2))
            }
        }
        throw XError.brightDataTimeout
    }

    private func normalizedUsername(for source: TrackedSource) throws -> String {
        let username = source.feedURL.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
        guard !username.isEmpty else { throw XError.invalidUsername }
        return username
    }

    private func twitterAPIIORequest(_ url: URL, apiKey: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        return try await responseData(for: request)
    }

    private func responseData(for request: URLRequest) async throws -> Data {
        try await response(for: request).0
    }

    private func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FeedError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw FeedError.http(http.statusCode) }
        return (data, http)
    }

    private func event(
        id: String,
        text: String,
        username: String,
        url: String,
        publishedAt: Date,
        metrics: XPost.PublicMetrics?,
        providerName: String,
        source: TrackedSource
    ) -> SignalEvent {
        let base = ImportanceScorer.score(text: text, topics: source.topics, kind: .x)
        let engagement = metrics.map {
            min(($0.likeCount / 1_000) + ($0.retweetCount / 250) + ($0.quoteCount / 100), 18)
        } ?? 0
        return SignalEvent(
            id: "\(source.id.uuidString)|x|\(id)",
            sourceID: source.id,
            sourceName: source.name,
            title: text.replacingOccurrences(of: "\n", with: " ").prefixText(120),
            summary: engagementSummary(metrics, providerName: providerName),
            url: url,
            publishedAt: publishedAt,
            category: .viewpoint,
            importance: min(base + engagement, 100),
            matchedTopics: ImportanceScorer.matchedTopics(in: text, topics: source.topics),
            domains: SignalDomainClassifier.classify(
                text: text,
                fallbackDomains: PersonPreset.defaultDomains(for: source),
                kind: .x
            )
        )
    }

    private func engagementSummary(
        _ metrics: XPost.PublicMetrics?,
        providerName: String
    ) -> String {
        guard let metrics else { return "来自 \(providerName)" }
        return "喜欢 \(metrics.likeCount.formatted()) · 转发 \(metrics.retweetCount.formatted()) · 回复 \(metrics.replyCount.formatted()) · 引用 \(metrics.quoteCount.formatted())"
    }
}

enum KeychainStore {
    private static let service = "com.tanghuaizhe.trackai"

    static var twitterAPIIOKey: String? {
        get { read(account: "twitterapi-io-api-key") }
        set { write(newValue, account: "twitterapi-io-api-key") }
    }

    static var brightDataAPIKey: String? {
        get { read(account: "bright-data-api-key") }
        set { write(newValue, account: "bright-data-api-key") }
    }

    static var deepSeekAPIKey: String? {
        get { read(account: "deepseek-api-key") }
        set { write(newValue, account: "deepseek-api-key") }
    }

    static var twelveDataAPIKey: String? {
        get { read(account: "twelve-data-api-key") }
        set { write(newValue, account: "twelve-data-api-key") }
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String?, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}

private struct BrightDataRequest: Encodable {
    var input: [Input]

    struct Input: Encodable {
        var urls: [String]
    }
}

private struct BrightDataSnapshot: Decodable {
    var snapshotId: String
}

private struct BrightDataSnapshotProgress: Decodable {
    var status: String
}

private struct BrightDataPost: Decodable {
    var id: String?
    var userPosted: String?
    var description: String?
    var datePosted: Date?
    var url: String?
    var replies: Int?
    var reposts: Int?
    var likes: Int?
    var quotes: Int?
    var parentPostDetails: ParentPostDetails?
    var error: String?

    var isRetweetPost: Bool {
        description?.hasPrefix("RT @") == true
    }

    var isReplyPost: Bool {
        guard let parentID = parentPostDetails?.postId, let id else { return false }
        return parentID != id
    }

    struct ParentPostDetails: Decodable {
        var postId: String?
    }
}

private struct TwitterAPIIOResponse: Decodable {
    var tweets: [XPost]?
}

private struct XPost: Decodable {
    var id: String
    var text: String
    var createdAt: Date?
    var retweetCount: Int?
    var replyCount: Int?
    var likeCount: Int?
    var quoteCount: Int?

    var metrics: PublicMetrics? {
        guard retweetCount != nil || replyCount != nil || likeCount != nil || quoteCount != nil else {
            return nil
        }
        return PublicMetrics(
            retweetCount: retweetCount ?? 0,
            replyCount: replyCount ?? 0,
            likeCount: likeCount ?? 0,
            quoteCount: quoteCount ?? 0
        )
    }

    struct PublicMetrics: Decodable {
        var retweetCount: Int
        var replyCount: Int
        var likeCount: Int
        var quoteCount: Int
    }
}

private extension JSONDecoder {
    static var xData: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let standard = ISO8601DateFormatter()
            if let date = standard.date(from: value) { return date }
            let twitter = DateFormatter()
            twitter.locale = Locale(identifier: "en_US_POSIX")
            twitter.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
            if let date = twitter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Invalid X data date: \(value)"
            )
        }
        return decoder
    }
}

private extension String {
    func prefixText(_ length: Int) -> String {
        String(prefix(length))
    }
}
