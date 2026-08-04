import Foundation

enum DailyBriefTopic: String, CaseIterable, Codable, Identifiable {
    case ai
    case embodiedAI
    case electricVehicles
    case chips

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ai: "AI 与大模型"
        case .embodiedAI: "具身智能与机器人"
        case .electricVehicles: "新能源汽车"
        case .chips: "芯片与算力"
        }
    }

    var query: String {
        switch self {
        case .ai: "(AI OR \"artificial intelligence\" OR 大模型 OR 人工智能) when:1d"
        case .embodiedAI: "(\"embodied AI\" OR robotics OR humanoid OR 具身智能 OR 人形机器人) when:1d"
        case .electricVehicles: "(\"electric vehicle\" OR EV OR \"autonomous driving\" OR 新能源汽车 OR 电动车) when:1d"
        case .chips: "(semiconductor OR GPU OR chip OR HBM OR 芯片 OR 半导体) when:1d"
        }
    }
}

struct DailyNewsItem: Hashable, Identifiable {
    var id: String
    var topic: DailyBriefTopic
    var title: String
    var summary: String
    var url: String?
    var publishedAt: Date

    var impactScore: Int {
        let ageHours = max(0, Date().timeIntervalSince(publishedAt) / 3_600)
        let titleText = title.lowercased()
        let impactTerms = [
            "launch", "approval", "regulation", "funding", "acquisition", "earnings",
            "partnership", "recall", "tariff", "export", "发布", "监管", "融资", "收购",
            "财报", "合作", "召回", "关税", "出口"
        ]
        let termBonus = impactTerms.filter(titleText.contains).count * 8
        return max(1, min(100, 76 - Int(ageHours * 2) + termBonus))
    }
}

struct DailyBrief: Codable, Hashable, Identifiable {
    var id: String
    var generatedAt: Date
    var windowStart: Date
    var windowEnd: Date
    var trackedEventCount: Int
    var newsItemCount: Int
    var provider: AISummaryProvider
    var content: String
}

struct DailyBriefService {
    func generate(
        events: [SignalEvent],
        news: [DailyNewsItem],
        windowStart: Date,
        windowEnd: Date
    ) async throws -> DailyBrief {
        let prompt = Self.prompt(
            events: events,
            news: news,
            windowStart: windowStart,
            windowEnd: windowEnd
        )
        let summary = try await AISummaryService().summarizePrompt(prompt)
        let dayID = ISO8601DateFormatter().string(from: windowEnd).prefix(10)
        return DailyBrief(
            id: String(dayID),
            generatedAt: Date(),
            windowStart: windowStart,
            windowEnd: windowEnd,
            trackedEventCount: events.count,
            newsItemCount: news.count,
            provider: summary.provider,
            content: summary.content
        )
    }

    static func prompt(
        events: [SignalEvent],
        news: [DailyNewsItem],
        windowStart: Date,
        windowEnd: Date
    ) -> String {
        let dateFormatter = ISO8601DateFormatter()
        let eventText = events.prefix(80).enumerated().map { index, event in
            """
            [已抓取情报 \(index + 1)] 来源：\(event.sourceName)；时间：\(dateFormatter.string(from: event.publishedAt))；评分：\(event.importance)
            标题：\(event.title)
            摘要：\(event.summary)
            """
        }.joined(separator: "\n\n")
        let newsText = news.prefix(24).enumerated().map { index, item in
            """
            [全网新闻 \(index + 1)] 主题：\(item.topic.title)；时间：\(dateFormatter.string(from: item.publishedAt))；影响力候选分：\(item.impactScore)
            标题：\(item.title)
            摘要：\(item.summary)
            原文链接：\(item.url ?? "未提供")
            """
        }.joined(separator: "\n\n")

        return """
        你是一名严谨的中文科技与投资情报主编。请生成一份每日快报，覆盖过去 24 小时的已抓取情报和全网新闻。
        时间窗口：\(dateFormatter.string(from: windowStart)) 至 \(dateFormatter.string(from: windowEnd))。
        目标是帮助投资者快速判断“发生了什么、为什么重要、哪些上市公司受到影响、还需要验证什么”。
        只依据输入材料；材料没有给出估值、财务数据或公司关系时，必须写“当前材料不足”，不得编造数字或把推测写成事实。
        输出详细 Markdown，不使用 Markdown 表格。

        严格使用以下结构：
        # 今日结论
        用 5–8 句话概括今日最重要的变化、最值得关注的主题和整体风险偏好。
        # 过去 24 小时已抓取情报
        按 AI、具身智能、新能源汽车、芯片与算力分组；覆盖主要人物观点、机构动态和持仓变化，合并重复信息并注明来源。
        # 影响力最大的全网新闻
        按影响力从高到低列出 8–12 条，不要只按发布时间排序。每条必须包含：
        - 事件事实：发生了什么、涉及谁、时间和关键数字
        - 影响公司：列出 1–3 家明确相关的上市公司，给出公司名和股票代码（无法确认代码时写“代码待核验”）
        - 方向：利好、利空或中性；不要为了凑数量强行给出方向
        - 受益/受损产品：明确指出哪条产品线、业务或供应链环节受影响
        - 传导逻辑：解释新闻如何影响收入、成本、竞争格局、资本开支或监管风险
        - 估值审查：若材料包含估值指标，判断当前估值是否偏高；若无法获得可靠估值，明确写“估值数据不足”，并说明需要什么增长、利润率、份额或现金流预期才能支撑估值
        - 反证与跟踪：列出一个会支持或推翻该判断的后续信号
        # 主题之间的共振与冲突
        说明四个主题之间有哪些共同驱动、产业链传导、相互冲突或市场可能误读的地方。
        # 今日最值得跟踪的公司清单
        只列 5–10 家，说明选择理由、利好/利空方向、产品和估值状态；不构成投资建议。
        # 明日验证清单
        列出 5–8 个应继续查证的财报、监管、产品发布、订单、价格或持仓信号。
        # 数据覆盖与局限
        写明已抓取情报数量、全网新闻数量、新闻搜索基于 Google News RSS 聚合而非完整互联网，并列出可能遗漏的内容。

        已抓取情报（共 \(events.count) 条）：
        \(eventText.isEmpty ? "过去 24 小时没有符合条件的已抓取情报。" : eventText)

        全网新闻候选（共 \(news.count) 条）：
        \(newsText.isEmpty ? "暂未获取到新闻候选。" : newsText)
        """
    }
}

struct NewsSearchClient {
    func search(now: Date = Date()) async throws -> [DailyNewsItem] {
        var results: [[DailyNewsItem]] = []
        await withTaskGroup(of: [DailyNewsItem].self) { group in
            for topic in DailyBriefTopic.allCases {
                group.addTask {
                    (try? await fetch(topic: topic, now: now)) ?? []
                }
            }
            for await items in group {
                results.append(items)
            }
        }

        var seen = Set<String>()
        return results
            .flatMap { $0 }
            .filter { $0.publishedAt >= now.addingTimeInterval(-24 * 3_600) }
            .sorted {
                if $0.impactScore != $1.impactScore { return $0.impactScore > $1.impactScore }
                return $0.publishedAt > $1.publishedAt
            }
            .filter { item in
                let key = item.title.lowercased()
                    .replacingOccurrences(of: "[^a-z0-9\\u4e00-\\u9fff]", with: "", options: .regularExpression)
                return seen.insert(key).inserted
            }
            .prefix(32)
            .map { $0 }
    }

    private func fetch(topic: DailyBriefTopic, now: Date) async throws -> [DailyNewsItem] {
        var components = URLComponents(string: "https://news.google.com/rss/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: topic.query),
            URLQueryItem(name: "hl", value: "zh-CN"),
            URLQueryItem(name: "gl", value: "CN"),
            URLQueryItem(name: "ceid", value: "CN:zh-Hans")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue("SignalDesk/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw FeedError.invalidResponse
        }
        return try FeedParser.parse(data: data)
            .filter { $0.publishedAt >= now.addingTimeInterval(-24 * 3_600) }
            .prefix(12)
            .map { item in
                DailyNewsItem(
                    id: "\(topic.rawValue)|\(item.link ?? item.title)",
                    topic: topic,
                    title: item.title,
                    summary: item.summary,
                    url: item.link,
                    publishedAt: item.publishedAt
                )
            }
    }
}
