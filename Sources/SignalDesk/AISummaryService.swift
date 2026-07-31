import CoreFoundation
import Foundation
import PDFKit

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AISummaryError: LocalizedError {
    case noUsableContent
    case localModelRequiresMacOS26
    case localModelUnavailable(String)
    case ollamaUnavailable(String)
    case localProvidersUnavailable(String)
    case missingDeepSeekKey
    case invalidResponse
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .noUsableContent:
            "没有可供总结的正文或简介"
        case .localModelRequiresMacOS26:
            "Apple 本机模型需要 macOS 26 或更高版本"
        case .localModelUnavailable(let reason):
            "Apple 本机模型暂不可用：\(reason)"
        case .ollamaUnavailable(let reason):
            "Ollama 本地模型不可用：\(reason)"
        case .localProvidersUnavailable(let reason):
            "免费本地模型暂不可用：\(reason)"
        case .missingDeepSeekKey:
            "未配置 DeepSeek API Key"
        case .invalidResponse:
            "AI 服务返回了无法解析的响应"
        case .http(let code, let message):
            "DeepSeek 返回 HTTP \(code)：\(message)"
        }
    }
}

struct AISummaryService {
    static let modeDefaultsKey = "ai-summary-mode"
    static let ollamaModelDefaultsKey = "ai-summary-ollama-model"
    static let defaultOllamaModel = "qwen3.5:4b"

    var mode: AISummaryMode {
        AISummaryMode(
            rawValue: UserDefaults.standard.string(forKey: Self.modeDefaultsKey) ?? ""
        ) ?? .localFirst
    }

    func summarize(_ event: SignalEvent) async throws -> AISummary {
        let articleText = await ArticleContentFetcher().content(for: event)
        guard !articleText.isEmpty else { throw AISummaryError.noUsableContent }
        return try await summarize(
            prompt: Self.prompt(
                event: event,
                articleText: Self.truncated(articleText, for: mode)
            )
        )
    }

    func summarize(_ writing: InvestorWriting) async throws -> AISummary {
        let articleText = await ArticleContentFetcher().content(
            title: writing.title,
            summary: writing.sourceNote,
            rawURL: writing.sourceURL
        )
        guard !articleText.isEmpty else { throw AISummaryError.noUsableContent }
        return try await summarize(
            prompt: Self.writingPrompt(
                writing: writing,
                articleText: Self.truncated(articleText, for: mode)
            )
        )
    }

    private func summarize(prompt: String) async throws -> AISummary {
        switch mode {
        case .deepSeek:
            return try await summarizeWithDeepSeek(prompt: prompt)
        case .ollama:
            return try await summarizeWithOllama(prompt: prompt)
        case .localFirst:
            do {
                return try await summarizeOnDevice(prompt: prompt)
            } catch let appleError {
                do {
                    return try await summarizeWithOllama(prompt: prompt)
                } catch let ollamaError {
                    throw AISummaryError.localProvidersUnavailable(
                        "Apple：\(appleError.localizedDescription)；Ollama：\(ollamaError.localizedDescription)"
                    )
                }
            }
        }
    }

    static var localAvailabilityDescription: String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "可用 · 内容不离开这台 Mac"
            case .unavailable(.deviceNotEligible):
                return "当前设备、系统或地区不具备使用资格"
            case .unavailable(.appleIntelligenceNotEnabled):
                return "请先在系统设置中开启 Apple Intelligence"
            case .unavailable(.modelNotReady):
                return "模型仍在下载或准备中"
            @unknown default:
                return "当前不可用"
            }
        }
        #endif
        return "需要 macOS 26 或更高版本"
    }

    private func summarizeOnDevice(prompt: String) async throws -> AISummary {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                let session = LanguageModelSession(
                    model: model,
                    instructions: Self.systemInstructions
                )
                let response = try await session.respond(to: prompt)
                return AISummary(
                    content: response.content.trimmingCharacters(in: .whitespacesAndNewlines),
                    provider: .appleOnDevice,
                    generatedAt: Date()
                )
            case .unavailable(.deviceNotEligible):
                throw AISummaryError.localModelUnavailable("设备不支持")
            case .unavailable(.appleIntelligenceNotEnabled):
                throw AISummaryError.localModelUnavailable("Apple Intelligence 未开启")
            case .unavailable(.modelNotReady):
                throw AISummaryError.localModelUnavailable("模型尚未准备完成")
            @unknown default:
                throw AISummaryError.localModelUnavailable("未知原因")
            }
        }
        #endif
        throw AISummaryError.localModelRequiresMacOS26
    }

    private func summarizeWithDeepSeek(prompt: String) async throws -> AISummary {
        guard let key = KeychainStore.deepSeekAPIKey, !key.isEmpty else {
            throw AISummaryError.missingDeepSeekKey
        }
        let content = try await DeepSeekClient().summarize(
            prompt: prompt,
            apiKey: key
        )
        return AISummary(content: content, provider: .deepSeek, generatedAt: Date())
    }

    private func summarizeWithOllama(prompt: String) async throws -> AISummary {
        let configured = UserDefaults.standard.string(forKey: Self.ollamaModelDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let model = configured.flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultOllamaModel
        let content = try await OllamaClient().summarize(
            prompt: prompt,
            model: model
        )
        return AISummary(content: content, provider: .ollama, generatedAt: Date())
    }

    private static let systemInstructions = """
    你是一名严谨的中文科技与投资情报分析师。只依据给定材料，不补造事实。
    区分受访者原话、媒体转述与分析推断；材料不足时明确说明。
    输出简洁中文，不使用 Markdown 表格。
    """

    private static func prompt(event: SignalEvent, articleText: String) -> String {
        """
        请总结下面这条关于 \(event.sourceName) 的内容。

        固定输出结构：
        一句话结论：不超过 60 字
        核心观点：
        - 3 至 5 条，每条尽量包含具体事实、数字或时间判断
        值得追踪的变化：
        - 相比其既有立场可能出现的新判断；无法判断则写“材料不足”
        投资/产业信号：
        - 1 至 3 条，并标注“事实”或“推断”
        可信度与缺口：
        - 说明内容是完整正文、节目简介还是其他材料，以及主要信息缺口

        标题：\(event.title)
        来源已有简介：\(event.summary)
        抓取内容：
        \(articleText)
        """
    }

    private static func writingPrompt(
        writing: InvestorWriting,
        articleText: String
    ) -> String {
        """
        请分析下面这份投资者材料。严格区分作者明确陈述、基金团队陈述和你的推断。

        固定输出结构：
        一句话结论：不超过 60 字
        核心投资观点：
        - 3 至 6 条，保留关键数字、估值、时间和条件
        持仓动作与理由：
        - 分别列出买入/增持、减持/退出、继续持有；材料未提及则明确写“未提及”
        相比上一期值得追踪的变化：
        - 只能依据本材料判断；缺少上期材料时写“需要与上期原文对比”
        风险、催化剂与反证条件：
        - 各 1 至 3 条，标注“原文”或“推断”
        与 13F 的核对提示：
        - 指出文中提到但仍需用申报持仓核验的公司或动作
        可信度与缺口：
        - 说明署名归属、材料是否完整，以及可能缺失的信息

        标题：\(writing.title)
        作者：\(writing.author)
        发布机构：\(writing.publisher)
        归属：\(writing.attribution.title)
        报告期：\(writing.period ?? "未标明")
        来源说明：\(writing.sourceNote)
        抓取内容：
        \(articleText)
        """
    }

    private static func truncated(_ text: String, for mode: AISummaryMode) -> String {
        let limit: Int
        switch mode {
        case .localFirst: limit = 12_000
        case .ollama: limit = 24_000
        case .deepSeek: limit = 40_000
        }
        return String(text.prefix(limit))
    }
}

struct ArticleContentFetcher {
    func content(for event: SignalEvent) async -> String {
        await content(title: event.title, summary: event.summary, rawURL: event.url)
    }

    func content(title: String, summary: String, rawURL: String?) async -> String {
        let fallback = [title, summary]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")

        guard let rawURL,
              let url = URL(string: rawURL),
              !Self.isVideoURL(url) else {
            return fallback
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue(
                "text/html,application/xhtml+xml,application/pdf",
                forHTTPHeaderField: "Accept"
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return fallback
            }
            let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            if contentType.contains("application/pdf") || url.pathExtension.lowercased() == "pdf" {
                let extracted = Self.extractPDFText(from: data)
                return extracted.count >= 240
                    ? String(extracted.prefix(40_000))
                    : fallback
            }
            guard let html = Self.decode(data: data, response: http) else { return fallback }
            let extracted = Self.extractReadableText(from: html)
            guard extracted.count >= 240 else { return fallback }
            return String(extracted.prefix(40_000))
        } catch {
            return fallback
        }
    }

    static func extractReadableText(from html: String) -> String {
        var candidate = html
        if let article = firstMatch(
            in: html,
            pattern: #"(?is)<article\b[^>]*>(.*?)</article>"#
        ) {
            candidate = article
        } else if let main = firstMatch(
            in: html,
            pattern: #"(?is)<main\b[^>]*>(.*?)</main>"#
        ) {
            candidate = main
        }

        candidate = replacing(pattern: #"(?is)<(script|style|noscript|svg|nav|footer|form)\b[^>]*>.*?</\1>"#, in: candidate, with: " ")
        candidate = replacing(pattern: #"(?i)<br\s*/?>|</p>|</div>|</li>|</h[1-6]>"#, in: candidate, with: "\n")
        candidate = replacing(pattern: #"(?s)<[^>]+>"#, in: candidate, with: " ")
        candidate = decodeEntities(candidate)
        candidate = replacing(pattern: #"[ \t]+"#, in: candidate, with: " ")
        candidate = replacing(pattern: #"\n\s*\n+"#, in: candidate, with: "\n\n")
        return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractPDFText(from data: Data) -> String {
        guard let document = PDFDocument(data: data) else { return "" }
        return (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decode(data: Data, response: HTTPURLResponse) -> String? {
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("charset=gb") {
            let encoding = String.Encoding(
                rawValue: CFStringConvertEncodingToNSStringEncoding(
                    CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
                )
            )
            return String(data: data, encoding: encoding)
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    private static func isVideoURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("youtube.com") || host == "youtu.be"
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func replacing(pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: replacement
        )
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = text
        let named = [
            "&nbsp;": " ", "&amp;": "&", "&quot;": "\"", "&#39;": "'",
            "&apos;": "'", "&lt;": "<", "&gt;": ">"
        ]
        for (entity, value) in named {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        guard let regex = try? NSRegularExpression(pattern: #"&#(x?[0-9a-fA-F]+);"#) else {
            return result
        }
        let matches = regex.matches(
            in: result,
            range: NSRange(result.startIndex..., in: result)
        ).reversed()
        for match in matches {
            guard let fullRange = Range(match.range(at: 0), in: result),
                  let valueRange = Range(match.range(at: 1), in: result) else { continue }
            let raw = String(result[valueRange])
            let radix = raw.lowercased().hasPrefix("x") ? 16 : 10
            let digits = radix == 16 ? String(raw.dropFirst()) : raw
            guard let value = UInt32(digits, radix: radix),
                  let scalar = UnicodeScalar(value) else { continue }
            result.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
        return result
    }
}

struct DeepSeekClient {
    func summarize(prompt: String, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://api.deepseek.com/chat/completions") else {
            throw FeedError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            DeepSeekRequest(
                model: "deepseek-v4-flash",
                messages: [
                    .init(role: "system", content: "你是一名严谨的中文科技与投资情报分析师，只依据材料总结。"),
                    .init(role: "user", content: prompt)
                ],
                thinking: .init(type: "disabled"),
                maxTokens: 1_200
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AISummaryError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(DeepSeekErrorResponse.self, from: data).error.message)
                ?? String(data: data, encoding: .utf8)
                ?? "未知错误"
            throw AISummaryError.http(http.statusCode, String(message.prefix(300)))
        }
        guard let content = try JSONDecoder().decode(DeepSeekResponse.self, from: data)
            .choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw AISummaryError.invalidResponse
        }
        return content
    }

    func validate(apiKey: String) async throws {
        guard let url = URL(string: "https://api.deepseek.com/models") else {
            throw FeedError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AISummaryError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(DeepSeekErrorResponse.self, from: data).error.message)
                ?? "验证失败"
            throw AISummaryError.http(http.statusCode, message)
        }
    }
}

struct OllamaClient {
    private let baseURL = URL(string: "http://127.0.0.1:11434")!

    func installedModels() async throws -> [String] {
        let url = baseURL.appending(path: "api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw AISummaryError.ollamaUnavailable("本地服务响应异常")
            }
            return try JSONDecoder().decode(OllamaTagsResponse.self, from: data).models.map(\.name)
        } catch let error as AISummaryError {
            throw error
        } catch {
            throw AISummaryError.ollamaUnavailable("未检测到服务，请先安装并启动 Ollama")
        }
    }

    func summarize(prompt: String, model: String) async throws -> String {
        let installed = try await installedModels()
        guard installed.contains(where: { $0 == model || $0.hasPrefix("\(model):") }) else {
            throw AISummaryError.ollamaUnavailable(
                "尚未下载 \(model)，请在终端运行 ollama run \(model)"
            )
        }

        let url = baseURL.appending(path: "api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OllamaRequest(
                model: model,
                messages: [
                    .init(role: "system", content: "你是一名严谨的中文科技与投资情报分析师，只依据材料总结。"),
                    .init(role: "user", content: prompt)
                ],
                stream: false
            )
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AISummaryError.ollamaUnavailable("本地服务响应无效")
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "未知错误"
                throw AISummaryError.ollamaUnavailable(String(message.prefix(300)))
            }
            let content = try JSONDecoder().decode(OllamaResponse.self, from: data)
                .message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { throw AISummaryError.invalidResponse }
            return content
        } catch let error as AISummaryError {
            throw error
        } catch {
            throw AISummaryError.ollamaUnavailable(error.localizedDescription)
        }
    }
}

private struct DeepSeekRequest: Encodable {
    struct Message: Encodable {
        var role: String
        var content: String
    }

    struct Thinking: Encodable {
        var type: String
    }

    var model: String
    var messages: [Message]
    var thinking: Thinking
    var maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, messages, thinking
        case maxTokens = "max_tokens"
    }
}

private struct DeepSeekResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String?
        }

        var message: Message
    }

    var choices: [Choice]
}

private struct DeepSeekErrorResponse: Decodable {
    struct APIError: Decodable {
        var message: String
    }

    var error: APIError
}

private struct OllamaTagsResponse: Decodable {
    struct Model: Decodable {
        var name: String
    }

    var models: [Model]
}

private struct OllamaRequest: Encodable {
    struct Message: Encodable {
        var role: String
        var content: String
    }

    var model: String
    var messages: [Message]
    var stream: Bool
}

private struct OllamaResponse: Decodable {
    struct Message: Decodable {
        var content: String
    }

    var message: Message
}
