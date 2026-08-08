import Foundation

struct CuratedSourcePreset: Identifiable, Hashable {
    var id: String
    var name: String
    var role: String
    var topics: [String]
    var feedURL: String

    func trackedSource() -> TrackedSource {
        TrackedSource(
            name: name,
            role: role,
            topics: topics,
            sourceKind: .rss,
            feedURL: feedURL
        )
    }
}

extension CuratedSourcePreset {
    static let researchSources: [CuratedSourcePreset] = [
        CuratedSourcePreset(
            id: "howard-marks-oaktree-memos",
            name: "Howard Marks / Oaktree Memos",
            role: "周期、风险、市场情绪与估值纪律；新 memo 必读；不是具体股票推荐",
            topics: ["market cycle", "risk", "market sentiment", "valuation", "credit", "周期", "风险", "估值", "信用"],
            feedURL: googleNewsFeed(query: "site:oaktreecapital.com/insights \"Howard Marks\"")
        ),
        CuratedSourcePreset(
            id: "aswath-damodaran-musings-on-markets",
            name: "Aswath Damodaran / Musings on Markets",
            role: "估值、反向 DCF 与把商业叙事转成可检验假设；估值依赖假设，不是目标价机器",
            topics: ["valuation", "DCF", "cost of capital", "narrative", "估值", "反向 DCF", "资本成本"],
            feedURL: "https://aswathdamodaran.blogspot.com/feeds/posts/default?alt=rss"
        ),
        CuratedSourcePreset(
            id: "stratechery",
            name: "Stratechery / Ben Thompson",
            role: "科技战略、平台、分发、价值捕获与利润池；战略洞察强于财务模型和估值",
            topics: ["technology strategy", "platform", "distribution", "value capture", "profit pool", "科技战略", "平台", "分发"],
            feedURL: "https://stratechery.com/feed/"
        ),
        CuratedSourcePreset(
            id: "money-stuff-matt-levine",
            name: "Money Stuff / Matt Levine",
            role: "并购、证券设计、监管、激励与市场机制；理解市场如何运作，不是选股服务",
            topics: ["merger", "acquisition", "securities", "regulation", "incentives", "market structure", "并购", "监管", "市场机制"],
            feedURL: "https://www.bloomberg.com/opinion/authors/ARbTQlRLRjE/matthew-s-levine.rss"
        ),
        CuratedSourcePreset(
            id: "the-diff-byrne-hobart",
            name: "The Diff / Byrne Hobart",
            role: "科技、金融与商业模式的非共识连接；用于寻找第二层问题，需回到一手资料核验",
            topics: ["technology", "finance", "business model", "strategy", "macroeconomics", "科技", "金融", "商业模式"],
            feedURL: "https://www.thediff.co/feed"
        ),
        CuratedSourcePreset(
            id: "semianalysis",
            name: "SemiAnalysis",
            role: "AI 加速器、数据中心、电力、网络、晶圆厂与成本结构；关注供应链瓶颈",
            topics: ["GPU", "ASIC", "HBM", "datacenter", "power", "networking", "foundry", "inference", "accelerator", "AI 加速器", "数据中心", "电力"],
            feedURL: "https://newsletter.semianalysis.com/feed"
        ),
        CuratedSourcePreset(
            id: "fabricated-knowledge",
            name: "Fabricated Knowledge",
            role: "用投资视角解释半导体公司与细分环节；优先阅读封装、量测、光刻、时钟与 CXL Primer",
            topics: ["semiconductor", "packaging", "metrology", "lithography", "timing", "CXL", "半导体", "封装", "量测", "光刻"],
            feedURL: "https://www.fabricatedknowledge.com/feed"
        ),
        CuratedSourcePreset(
            id: "a16z-show",
            name: "The a16z Show",
            role: "AI 创业、产品、基础设施与科技产业前沿访谈；关注芯片、数据中心与 AI 商业化",
            topics: ["AI", "startup", "product", "infrastructure", "chip", "datacenter", "AI commercialization", "创业", "基础设施", "商业化"],
            feedURL: "https://feeds.simplecast.com/JGE3yC0V"
        ),
        CuratedSourcePreset(
            id: "ai-a16z",
            name: "AI + a16z",
            role: "AI 技术与商业模式专题；关注 Agent、评测、数据、AI 定价与企业部署",
            topics: ["AI", "agent", "evaluation", "data", "pricing", "enterprise deployment", "AI infrastructure", "Agent", "评测", "企业部署"],
            feedURL: "https://feeds.simplecast.com/Hb_IuXOo"
        )
    ]

    private static func googleNewsFeed(query: String) -> String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "news.google.com"
        components.path = "/rss/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "hl", value: "en-US"),
            URLQueryItem(name: "gl", value: "US"),
            URLQueryItem(name: "ceid", value: "US:en")
        ]
        return components.url!.absoluteString
    }
}
