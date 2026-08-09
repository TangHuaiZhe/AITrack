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
    static let automaticSummaryImportanceThreshold = 60

    var mode: AISummaryMode {
        AISummaryMode(
            rawValue: UserDefaults.standard.string(forKey: Self.modeDefaultsKey) ?? ""
        ) ?? .localFirst
    }

    func summarize(_ event: SignalEvent) async throws -> AISummary {
        let articleText = await ArticleContentFetcher().content(for: event)
        guard !articleText.isEmpty else { throw AISummaryError.noUsableContent }
        return try await summarizePrompt(
            Self.prompt(
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
        return try await summarizePrompt(
            Self.writingPrompt(
                writing: writing,
                articleText: Self.truncated(articleText, for: mode)
            )
        )
    }

    func summarizePrompt(_ prompt: String) async throws -> AISummary {
        try await generate(prompt: prompt, instructions: Self.systemInstructions)
    }

    func translate(_ event: SignalEvent) async throws -> AITranslation {
        let articleText = await ArticleContentFetcher().content(for: event)
        guard !articleText.isEmpty else { throw AISummaryError.noUsableContent }
        let result = try await generate(
            prompt: Self.translationPrompt(
                title: event.title,
                sourceName: event.sourceName,
                summary: event.summary,
                articleText: Self.truncated(articleText, for: mode)
            ),
            instructions: Self.translationInstructions
        )
        return AITranslation(
            content: result.content,
            provider: result.provider,
            generatedAt: result.generatedAt
        )
    }

    func translate(_ writing: InvestorWriting) async throws -> AITranslation {
        let articleText = await ArticleContentFetcher().content(
            title: writing.title,
            summary: writing.sourceNote,
            rawURL: writing.sourceURL
        )
        guard !articleText.isEmpty else { throw AISummaryError.noUsableContent }
        let result = try await generate(
            prompt: Self.translationPrompt(
                title: writing.title,
                sourceName: writing.publisher,
                summary: writing.sourceNote,
                articleText: Self.truncated(articleText, for: mode)
            ),
            instructions: Self.translationInstructions
        )
        return AITranslation(
            content: result.content,
            provider: result.provider,
            generatedAt: result.generatedAt
        )
    }

    private func generate(prompt: String, instructions: String) async throws -> AISummary {
        switch mode {
        case .deepSeek:
            return try await summarizeWithDeepSeek(prompt: prompt, instructions: instructions)
        case .ollama:
            return try await summarizeWithOllama(prompt: prompt, instructions: instructions)
        case .localFirst:
            do {
                return try await summarizeOnDevice(prompt: prompt, instructions: instructions)
            } catch let appleError {
                do {
                    return try await summarizeWithOllama(prompt: prompt, instructions: instructions)
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

    private func summarizeOnDevice(prompt: String, instructions: String) async throws -> AISummary {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                let session = LanguageModelSession(
                    model: model,
                    instructions: instructions
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

    private func summarizeWithDeepSeek(prompt: String, instructions: String) async throws -> AISummary {
        guard let key = KeychainStore.deepSeekAPIKey, !key.isEmpty else {
            throw AISummaryError.missingDeepSeekKey
        }
        let content = try await DeepSeekClient().summarize(
            prompt: prompt,
            apiKey: key,
            systemInstructions: instructions
        )
        return AISummary(content: content, provider: .deepSeek, generatedAt: Date())
    }

    private func summarizeWithOllama(prompt: String, instructions: String) async throws -> AISummary {
        let configured = UserDefaults.standard.string(forKey: Self.ollamaModelDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let model = configured.flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultOllamaModel
        let content = try await OllamaClient().summarize(
            prompt: prompt,
            model: model,
            systemInstructions: instructions
        )
        return AISummary(content: content, provider: .ollama, generatedAt: Date())
    }

    private static let systemInstructions = """
    你是一名严谨的中文科技与投资情报分析师。你的任务是完整覆盖给定材料，而不是只写几句摘要。
    只依据给定材料，不补造事实；区分作者/受访者原话、媒体转述与分析推断，材料不足时明确说明。
    保留材料中的公司名、人名、数字、时间、因果关系和限定条件。输出结构化 Markdown，不使用 Markdown 表格。
    """

    private static let translationInstructions = """
    你是一名严谨的中文科技与投资材料翻译。只翻译给定材料，不总结、不解释、不补充事实。
    输出简体中文译文，保留原文的段落、列表、Markdown 标记、公司名、人名、数字、日期、单位和限定条件。
    专有名词首次出现时可保留英文括注；无法确定的术语保留原文，不要臆造译法。
    """

    static func prompt(event: SignalEvent, articleText: String) -> String {
        """
        请对下面这条关于 \(event.sourceName) 的材料做一份“完整情报拆解”，不要只给三五句摘要。
        目标长度约 800–1,500 个中文字符；如果材料很长，按主要段落和主题覆盖，不要只挑开头或最醒目的观点。
        材料没有明确回答的内容必须写“材料未提及”，不得用常识补全。

        严格使用下面的 Markdown 结构，并覆盖材料中的每个主要主题：
        # 一句话结论
        用 1–2 句说清材料最重要的判断和它的适用条件。
        # 内容概览
        用一段话说明材料在讨论什么、由谁提出、面向什么场景；不要重复标题。
        # 关键事实与数据
        至少列出 4 条材料明确给出的事实、数字、时间、公司或人物；没有数字时不要编造数字。
        # 主要观点与论证链
        按“观点 → 原文依据 → 得出的含义”逐条拆解，至少覆盖 4 个主要观点；区分明确陈述和分析推断。
        # 时间判断与变化
        列出材料中的时间表、预测、前后变化和触发条件；没有时间判断则明确写出。
        # 对行业与投资的影响
        分别说明对技术路线、产业链、公司经营或投资决策的可能影响，并给每条标注“材料事实”或“分析推断”。
        # 风险、反例与不确定性
        列出材料自身承认的风险、尚未解决的问题、可能的反例和信息缺口。
        # 值得继续跟踪
        给出 3–5 个可验证的问题或后续信号，说明未来看到什么信息才会支持或推翻当前判断。
        # 原文覆盖说明
        说明本次实际依据的是完整正文、网页摘录、节目简介还是标题；指出可能没有被抓取到的部分。

        标题：\(event.title)
        来源已有简介：\(event.summary)
        本次送入模型的材料长度：\(articleText.count) 字
        抓取内容（请完整覆盖以下材料）：
        \(articleText)
        """
    }

    static func translationPrompt(event: SignalEvent, articleText: String) -> String {
        translationPrompt(
            title: event.title,
            sourceName: event.sourceName,
            summary: event.summary,
            articleText: articleText
        )
    }

    static func translationPrompt(writing: InvestorWriting, articleText: String) -> String {
        translationPrompt(
            title: writing.title,
            sourceName: writing.publisher,
            summary: writing.sourceNote,
            articleText: articleText
        )
    }

    private static func translationPrompt(
        title: String,
        sourceName: String,
        summary: String,
        articleText: String
    ) -> String {
        """
        请将下面来自 \(sourceName) 的材料完整翻译为简体中文。
        只输出译文，不要输出“翻译如下”、摘要、评论、解释或翻译过程。
        不要删减内容；保留段落、列表、Markdown 标记、数字、时间、公司名、人名、单位和语气限定。
        标题：\(title)
        来源简介：\(summary)
        原文材料：
        \(articleText)
        """
    }

    static func writingPrompt(
        writing: InvestorWriting,
        articleText: String
    ) -> String {
        """
        请对下面这份投资者材料做一份完整的中文投资分析，不要只给几句摘要。
        目标长度约 1,000–2,000 个中文字符；按材料的主要章节、主题和论点覆盖全文。
        严格区分作者明确陈述、基金团队陈述、历史事实和你的推断；材料未提及的内容写“材料未提及”。

        严格使用下面的 Markdown 结构，并覆盖材料中的每个主要主题：
        # 执行摘要
        用 2–3 句说清这份材料的核心判断、适用条件和最重要的变化。
        # 材料背景与作者立场
        说明作者/机构、报告期、写作目的，以及哪些内容是作者明确陈述。
        # 核心投资观点
        至少列出 5 条，逐条写出“观点 → 原文依据 → 对估值/经营的含义”；保留关键数字、估值、时间和条件。
        # 公司、行业与宏观判断
        覆盖材料提到的主要公司、行业、宏观变量和它们之间的因果关系；不要只写材料最前面的公司。
        # 持仓动作与资本配置
        分别列出买入/增持、减持/退出、继续持有、回购/分红或现金配置；每项写理由，材料未提及则明确写出。
        # 业绩、估值与关键指标
        汇总材料中的收入、利润、现金流、估值、回报率、目标价或其他量化信息，并保留原单位和时间范围。
        # 相比上一期的变化
        只能依据本材料判断；缺少上期材料时写“需要与上期原文对比”，不要臆测变化。
        # 风险、催化剂与反证条件
        各列出 2–4 条，并标注“原文”或“推断”；说明什么情况会推翻当前判断。
        # 与 13F 和后续信息的核对提示
        指出需要用申报持仓、财报、下一封信或其他来源验证的公司、动作和判断。
        # 原文覆盖说明
        说明本次依据的是完整信件、网页摘录还是来源简介，以及可能缺失的章节或数据。

        标题：\(writing.title)
        作者：\(writing.author)
        发布机构：\(writing.publisher)
        归属：\(writing.attribution.title)
        报告期：\(writing.period ?? "未标明")
        来源说明：\(writing.sourceNote)
        本次送入模型的材料长度：\(articleText.count) 字
        抓取内容（请完整覆盖以下材料）：
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
    func summarize(
        prompt: String,
        apiKey: String,
        systemInstructions: String = "你是一名严谨的中文科技与投资情报分析师，只依据材料总结。"
    ) async throws -> String {
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
                    .init(role: "system", content: systemInstructions),
                    .init(role: "user", content: prompt)
                ],
                thinking: .init(type: "disabled"),
                maxTokens: 2_600
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

    func summarize(
        prompt: String,
        model: String,
        systemInstructions: String = "你是一名严谨的中文科技与投资情报分析师，只依据材料总结。"
    ) async throws -> String {
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
                    .init(role: "system", content: systemInstructions),
                    .init(role: "user", content: prompt)
                ],
                stream: false,
                options: .init(numPredict: 2_600)
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
    var options: Options

    struct Options: Encodable {
        var numPredict: Int

        enum CodingKeys: String, CodingKey {
            case numPredict = "num_predict"
        }
    }
}

private struct OllamaResponse: Decodable {
    struct Message: Decodable {
        var content: String
    }

    var message: Message
}
