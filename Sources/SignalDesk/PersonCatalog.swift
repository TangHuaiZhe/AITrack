import Foundation

struct PersonPreset: Identifiable, Hashable {
    var id: String
    var name: String
    var stance: String
    var horizon: String
    var variables: [String]
    var xUsername: String?
    var xNote: String?
    var feeds: [PresetFeed]

    func trackedSources() -> [TrackedSource] {
        let aliases = name
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var result = [
            TrackedSource(
                name: "\(name) · 长内容",
                role: "采访、播客、演讲与视频索引；打开原文确认完整语境",
                topics: variables + aliases,
                sourceKind: .mediaSearch,
                feedURL: Self.mediaFeed(aliases: aliases),
                requiredTitleTerms: aliases
            )
        ]
        result += feeds.map { feed in
            TrackedSource(
                name: "\(name) · \(feed.label)",
                role: feed.role,
                topics: variables,
                sourceKind: .rss,
                feedURL: feed.url
            )
        }
        return result
    }

    static var legacyXUsernames: Set<String> {
        Set(aiRoboticsLeaders.compactMap(\.xUsername).map { $0.lowercased() })
    }

    private static func mediaFeed(aliases: [String]) -> String {
        let subject = aliases.map { "\"\($0)\"" }.joined(separator: " OR ")
        let intent = "(intitle:interview OR intitle:podcast OR intitle:keynote OR intitle:conversation OR intitle:\"fireside chat\" OR intitle:\"Q&A\" OR intitle:访谈 OR intitle:专访 OR intitle:对话 OR intitle:播客 OR intitle:演讲 OR intitle:圆桌)"
        var components = URLComponents()
        components.scheme = "https"
        components.host = "news.google.com"
        components.path = "/rss/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: "(\(subject)) \(intent)"),
            URLQueryItem(name: "hl", value: "en-US"),
            URLQueryItem(name: "gl", value: "US"),
            URLQueryItem(name: "ceid", value: "US:en")
        ]
        return components.url!.absoluteString
    }
}

struct PresetFeed: Hashable {
    var label: String
    var role: String
    var url: String
}

extension PersonPreset {
    static let aiRoboticsLeaders: [PersonPreset] = [
        PersonPreset(
            id: "elon-musk",
            name: "马斯克 / Elon Musk",
            stance: "超级智能不可阻挡，AI 与机器人将带来极度富足",
            horizon: "约 5 年超过全人类",
            variables: ["Optimus", "robot", "autonomy", "FSD", "AI safety", "energy", "机器人", "自动驾驶", "AI 安全", "能源"],
            xUsername: "elonmusk",
            xNote: "本人 X · 高频，需重点筛选",
            feeds: []
        ),
        PersonPreset(
            id: "demis-hassabis",
            name: "Demis Hassabis",
            stance: "AGI 将首先成为科学发现引擎",
            horizon: "约 2030 年，或未来 5–10 年",
            variables: ["AGI", "AI scientist", "world model", "governance", "science", "AlphaFold", "科学发现", "世界模型", "治理"],
            xUsername: "demishassabis",
            xNote: "本人 X · 直接观点",
            feeds: [
                PresetFeed(
                    label: "DeepMind 视频",
                    role: "Google DeepMind 官方一手输出",
                    url: youtubeFeed("UCP7jMXSY2xbc3KCAE0MHQ-A")
                )
            ]
        ),
        PersonPreset(
            id: "dario-amodei",
            name: "Dario Amodei",
            stance: "强大 AI 极近，就业与安全冲击需要提前准备",
            horizon: "未来 1–2 年可能出现 Powerful AI",
            variables: ["powerful AI", "automation", "coding", "employment", "biosecurity", "alignment", "AI safety", "编程自动化", "白领就业", "生物安全"],
            xUsername: nil,
            xNote: nil,
            feeds: [
                PresetFeed(
                    label: "Anthropic 视频",
                    role: "官方演讲、访谈与发布；个人 X 当前不可用",
                    url: youtubeFeed("UCrDwWp7EBBv4NwvScIpBDOA")
                )
            ]
        ),
        PersonPreset(
            id: "jensen-huang",
            name: "黄仁勋 / Jensen Huang",
            stance: "AI 是新工业基础设施，将进入 Agent 和 Physical AI 阶段",
            horizon: "不强调单一 AGI 日期",
            variables: ["AI factory", "GPU", "robot", "physical AI", "agent", "energy", "inference", "AI 工厂", "机器人", "能源消耗", "推理"],
            xUsername: "JensenHuang",
            xNote: "本人 X · 2026 年开通",
            feeds: [
                PresetFeed(
                    label: "NVIDIA Robotics",
                    role: "NVIDIA 官方机器人动态",
                    url: "https://nvidianews.nvidia.com/cats/robotics.xml"
                )
            ]
        ),
        PersonPreset(
            id: "yann-lecun",
            name: "Yann LeCun",
            stance: "LLM 无法单独通向人类级智能",
            horizon: "世界模型可能需要数年成熟",
            variables: ["JEPA", "world model", "open source", "AMI", "LLM", "reasoning", "世界模型", "开放模型"],
            xUsername: "ylecun",
            xNote: "本人 X · 已转为低频输出",
            feeds: []
        ),
        PersonPreset(
            id: "fei-fei-li",
            name: "李飞飞 / Fei-Fei Li",
            stance: "下一个前沿是空间智能，而不仅是语言智能",
            horizon: "不设明确 AGI 日期",
            variables: ["spatial intelligence", "world model", "3D", "robot", "human-centered AI", "computer vision", "空间智能", "世界模型", "机器人"],
            xUsername: "drfeifei",
            xNote: "本人 X · 直接观点与研究输出",
            feeds: []
        ),
        PersonPreset(
            id: "andrej-karpathy",
            name: "Andrej Karpathy",
            stance: "软件进入 Software 3.0，但 Agent 仍不可靠",
            horizon: "不强调 AGI 日期",
            variables: ["Software 3.0", "agent", "coding", "LLM", "vibe coding", "human AI collaboration", "AI 编程", "Agent 工程", "人机协同"],
            xUsername: "karpathy",
            xNote: "本人 X · 高频技术观点",
            feeds: [
                PresetFeed(
                    label: "个人 YouTube",
                    role: "本人长篇课程与技术解释",
                    url: youtubeFeed("UCXUPKJO5MZQN11PqgIvyuvQ")
                )
            ]
        ),
        PersonPreset(
            id: "wang-xingxing",
            name: "王兴兴",
            stance: "人形机器人硬件快速成熟，但“大脑”仍是瓶颈",
            horizon: "关注 2026 年量产与交付",
            variables: ["humanoid", "Unitree", "G1", "H1", "mass production", "cost", "embodied AI", "人形机器人", "量产", "成本", "具身智能", "家庭应用"],
            xUsername: nil,
            xNote: nil,
            feeds: [
                PresetFeed(
                    label: "宇树官方视频",
                    role: "公司一手产品与技术输出；非个人发言",
                    url: youtubeFeed("UCsMbp4V8oxzHCMdOUP-3oWw")
                )
            ]
        ),
        PersonPreset(
            id: "jim-fan",
            name: "Jim Fan",
            stance: "机器人需要基础模型、仿真和真实数据共同训练",
            horizon: "不设明确日期",
            variables: ["VLA", "GR00T", "simulation", "synthetic data", "robot foundation model", "physical AI", "仿真", "合成数据", "机器人基础模型"],
            xUsername: "DrJimFan",
            xNote: "本人 X · 主要公开输出渠道",
            feeds: []
        ),
        PersonPreset(
            id: "lisa-su",
            name: "苏姿丰 / Lisa Su",
            stance: "AI 算力需求仍将指数增长，并从云端走向终端",
            horizon: "关注未来五年算力扩张",
            variables: ["GPU competition", "MI300", "MI400", "open ecosystem", "inference cost", "edge AI", "Yottaflops", "GPU 竞争", "开放生态", "推理成本"],
            xUsername: "LisaSu",
            xNote: "本人 X · AMD 战略与产品",
            feeds: []
        ),
        PersonPreset(
            id: "satya-nadella",
            name: "Satya Nadella",
            stance: "AI 的价值最终体现为企业工作流和生产率",
            horizon: "Agent 已从回答走向执行任务",
            variables: ["enterprise agent", "Copilot", "workflow", "productivity", "software business model", "agentic AI", "企业 Agent", "工作流", "生产率"],
            xUsername: "satyanadella",
            xNote: "本人 X · 企业 AI 战略",
            feeds: []
        )
    ]

    private static func youtubeFeed(_ channelID: String) -> String {
        "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelID)"
    }
}
