import Foundation
import Security

enum XError: LocalizedError {
    case missingToken
    case invalidUsername
    case userNotFound

    var errorDescription: String? {
        switch self {
        case .missingToken: "尚未在设置中保存 X API Bearer Token"
        case .invalidUsername: "X 用户名无效"
        case .userNotFound: "X API 未返回该用户"
        }
    }
}

struct XClient {
    func fetch(_ source: TrackedSource) async throws -> [SignalEvent] {
        guard let token = KeychainStore.xBearerToken, !token.isEmpty else {
            throw XError.missingToken
        }
        let username = source.feedURL.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !username.isEmpty,
              let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw XError.invalidUsername
        }

        let lookupURL = URL(string: "https://api.x.com/2/users/by/username/\(encodedUsername)")!
        let lookupData = try await request(lookupURL, token: token)
        guard let user = try JSONDecoder().decode(XUserResponse.self, from: lookupData).data else {
            throw XError.userNotFound
        }

        var components = URLComponents(string: "https://api.x.com/2/users/\(user.id)/tweets")!
        components.queryItems = [
            URLQueryItem(name: "max_results", value: "20"),
            URLQueryItem(name: "exclude", value: "retweets,replies"),
            URLQueryItem(name: "tweet.fields", value: "created_at,public_metrics")
        ]
        let timelineData = try await request(components.url!, token: token)
        return try events(from: timelineData, user: user, source: source)
    }

    func events(from data: Data, user: XUser, source: TrackedSource) throws -> [SignalEvent] {
        let timeline = try JSONDecoder.xAPI.decode(XTimelineResponse.self, from: data)
        return (timeline.data ?? []).map { post in
            let base = ImportanceScorer.score(text: post.text, topics: source.topics, kind: .x)
            let engagement = post.publicMetrics.map {
                min(($0.likeCount / 1_000) + ($0.retweetCount / 250) + ($0.quoteCount / 100), 18)
            } ?? 0
            return SignalEvent(
                id: "\(source.id.uuidString)|x|\(post.id)",
                sourceID: source.id,
                sourceName: source.name,
                title: post.text.replacingOccurrences(of: "\n", with: " ").prefixText(120),
                summary: engagementSummary(post.publicMetrics),
                url: "https://x.com/\(user.username)/status/\(post.id)",
                publishedAt: post.createdAt ?? Date(),
                category: .viewpoint,
                importance: min(base + engagement, 100),
                matchedTopics: ImportanceScorer.matchedTopics(in: post.text, topics: source.topics),
                domains: SignalDomainClassifier.classify(
                    text: post.text,
                    fallbackDomains: PersonPreset.defaultDomains(for: source),
                    kind: .x
                )
            )
        }
    }

    func validateToken(_ token: String) async throws {
        let url = URL(string: "https://api.x.com/2/users/by/username/XDevelopers")!
        _ = try await request(url, token: token)
    }

    private func request(_ url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FeedError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw FeedError.http(http.statusCode) }
        return data
    }

    private func engagementSummary(_ metrics: XPost.PublicMetrics?) -> String {
        guard let metrics else { return "来自 X 官方 API" }
        return "喜欢 \(metrics.likeCount.formatted()) · 转发 \(metrics.retweetCount.formatted()) · 回复 \(metrics.replyCount.formatted()) · 引用 \(metrics.quoteCount.formatted())"
    }
}

enum KeychainStore {
    private static let service = "com.tanghuaizhe.trackai"

    static var xBearerToken: String? {
        get { read(account: "x-api-bearer-token") }
        set { write(newValue, account: "x-api-bearer-token") }
    }

    static var deepSeekAPIKey: String? {
        get { read(account: "deepseek-api-key") }
        set { write(newValue, account: "deepseek-api-key") }
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

struct XUserResponse: Decodable {
    var data: XUser?
}

struct XUser: Decodable {
    var id: String
    var username: String
}

struct XTimelineResponse: Decodable {
    var data: [XPost]?
}

struct XPost: Decodable {
    var id: String
    var text: String
    var createdAt: Date?
    var publicMetrics: PublicMetrics?

    struct PublicMetrics: Decodable {
        var retweetCount: Int
        var replyCount: Int
        var likeCount: Int
        var quoteCount: Int
    }
}

private extension JSONDecoder {
    static var xAPI: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let standard = ISO8601DateFormatter()
            if let date = standard.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Invalid X API ISO-8601 date: \(value)"
            )
        }
        return decoder
    }
}

private extension Substring {
    func prefixText(_ length: Int) -> String {
        String(prefix(length))
    }
}

private extension String {
    func prefixText(_ length: Int) -> String {
        String(prefix(length))
    }
}
