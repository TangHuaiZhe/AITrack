import Foundation

enum XBloggerCategory: String, CaseIterable, Identifiable {
    case ai
    case robotics
    case compute
    case investment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ai: "AI 与大模型"
        case .robotics: "机器人"
        case .compute: "芯片与算力"
        case .investment: "投资"
        }
    }
}

struct XBloggerPreset: Identifiable, Hashable {
    var id: String
    var name: String
    var username: String
    var category: XBloggerCategory
    var role: String
    var topics: [String]
    var isRecommended: Bool
    var note: String? = nil

    func trackedSource(isEnabled: Bool) -> TrackedSource {
        .x(
            name: name,
            role: "\(category.title) · \(role)",
            username: username,
            topics: topics,
            isEnabled: isEnabled
        )
    }
}

extension XBloggerPreset {
    static let catalog: [XBloggerPreset] = [
        XBloggerPreset(
            id: "andrej-karpathy", name: "Andrej Karpathy", username: "karpathy",
            category: .ai, role: "AI 教育、LLM 与 Agent 工程",
            topics: ["LLM", "Agent", "AI coding", "Software 3.0", "模型", "AI 编程"],
            isRecommended: true
        ),
        XBloggerPreset(
            id: "demis-hassabis", name: "Demis Hassabis", username: "demishassabis",
            category: .ai, role: "AGI、科学发现与世界模型",
            topics: ["AGI", "AI scientist", "world model", "AlphaFold", "科学发现"],
            isRecommended: true
        ),
        XBloggerPreset(
            id: "fei-fei-li", name: "李飞飞 / Fei-Fei Li", username: "drfeifei",
            category: .ai, role: "空间智能、计算机视觉与以人为本 AI",
            topics: ["spatial intelligence", "computer vision", "world model", "空间智能"],
            isRecommended: true
        ),
        XBloggerPreset(
            id: "andrew-ng", name: "Andrew Ng", username: "AndrewYNg",
            category: .ai, role: "AI 应用、教育与创业",
            topics: ["AI applications", "AI education", "startup", "agentic AI", "AI 应用"],
            isRecommended: true
        ),
        XBloggerPreset(
            id: "sam-altman", name: "Sam Altman", username: "sama",
            category: .ai, role: "前沿模型、产品与 AI 产业",
            topics: ["OpenAI", "AGI", "model", "compute", "AI product", "算力"],
            isRecommended: false
        ),
        XBloggerPreset(
            id: "yann-lecun", name: "Yann LeCun", username: "ylecun",
            category: .ai, role: "世界模型、开放研究与 AI 路线争论",
            topics: ["JEPA", "world model", "open source", "LLM", "世界模型"],
            isRecommended: false
        ),

        XBloggerPreset(
            id: "jim-fan", name: "Jim Fan", username: "DrJimFan",
            category: .robotics, role: "机器人基础模型、仿真与 Physical AI",
            topics: ["VLA", "GR00T", "robot foundation model", "simulation", "Physical AI"],
            isRecommended: true
        ),
        XBloggerPreset(
            id: "chelsea-finn", name: "Chelsea Finn", username: "chelseabfinn",
            category: .robotics, role: "机器人学习、VLA 与 Physical Intelligence",
            topics: ["robot learning", "VLA", "imitation learning", "Physical Intelligence"],
            isRecommended: true
        ),
        XBloggerPreset(
            id: "sergey-levine", name: "Sergey Levine", username: "svlevine",
            category: .robotics, role: "通用机器人模型与强化学习",
            topics: ["robot learning", "reinforcement learning", "generalist robot", "VLA"],
            isRecommended: true
        ),
        XBloggerPreset(
            id: "elon-musk", name: "马斯克 / Elon Musk", username: "elonmusk",
            category: .robotics, role: "Optimus、自动驾驶与 AI 基础设施",
            topics: ["Optimus", "FSD", "autonomy", "robot", "AI", "自动驾驶"],
            isRecommended: true
        ),
        XBloggerPreset(
            id: "russ-tedrake", name: "Russ Tedrake", username: "RussTedrake",
            category: .robotics, role: "机器人控制、运动规划与研究",
            topics: ["robotics", "control", "motion planning", "manipulation"],
            isRecommended: false
        ),
        XBloggerPreset(
            id: "pieter-abbeel", name: "Pieter Abbeel", username: "pabbeel",
            category: .robotics, role: "机器人学习与 AI 创业",
            topics: ["robot learning", "reinforcement learning", "embodied AI", "机器人"],
            isRecommended: false
        ),

        XBloggerPreset(
            id: "dylan-patel", name: "Dylan Patel", username: "dylan522p",
            category: .compute, role: "AI 芯片、供应链与数据中心分析",
            topics: ["GPU", "AI accelerator", "HBM", "datacenter", "semiconductor", "芯片"],
            isRecommended: true
        ),
        XBloggerPreset(
            id: "ian-cutress", name: "Ian Cutress", username: "IanCutress",
            category: .compute, role: "CPU、半导体与硬件架构分析",
            topics: ["CPU", "GPU", "semiconductor", "architecture", "memory", "硬件"],
            isRecommended: true
        ),
        XBloggerPreset(
            id: "lisa-su", name: "苏姿丰 / Lisa Su", username: "LisaSu",
            category: .compute, role: "AMD 战略、AI 算力与产品",
            topics: ["AMD", "GPU", "MI300", "datacenter", "AI compute", "算力"],
            isRecommended: true
        ),
        XBloggerPreset(
            id: "jensen-huang", name: "黄仁勋 / Jensen Huang", username: "JensenHuang",
            category: .compute, role: "AI 工厂、GPU 与 Physical AI",
            topics: ["NVIDIA", "GPU", "AI factory", "Physical AI", "inference", "AI 工厂"],
            isRecommended: true
        ),
        XBloggerPreset(
            id: "patrick-moorhead", name: "Patrick Moorhead", username: "PatrickMoorhead",
            category: .compute, role: "企业科技、芯片与基础设施分析",
            topics: ["semiconductor", "cloud", "datacenter", "enterprise AI", "芯片"],
            isRecommended: false
        ),
        XBloggerPreset(
            id: "david-kanter", name: "David Kanter", username: "TheKanter",
            category: .compute, role: "芯片架构、性能与机器学习硬件",
            topics: ["chip architecture", "GPU", "ML hardware", "performance", "芯片架构"],
            isRecommended: false
        ),

        XBloggerPreset(
            id: "ray-dalio", name: "瑞·达利欧 / Ray Dalio", username: "RayDalio",
            category: .investment, role: "宏观周期、债务与世界秩序",
            topics: ["debt cycle", "monetary policy", "world order", "gold", "债务周期"],
            isRecommended: true
        ),
        XBloggerPreset(
            id: "aswath-damodaran", name: "Aswath Damodaran", username: "AswathDamodaran",
            category: .investment, role: "公司估值、资本成本与市场叙事",
            topics: ["valuation", "cost of capital", "equity risk", "narrative", "估值"],
            isRecommended: true
        ),
        XBloggerPreset(
            id: "howard-marks", name: "Howard Marks", username: "HowardMarksBook",
            category: .investment, role: "市场周期、风险与逆向投资",
            topics: ["market cycle", "risk", "credit", "contrarian", "市场周期"],
            isRecommended: true,
            note: "由 Howard Marks 团队运营"
        ),
        XBloggerPreset(
            id: "lyn-alden", name: "Lyn Alden", username: "LynAldenContact",
            category: .investment, role: "全球宏观、流动性与货币体系",
            topics: ["macro", "liquidity", "fiscal policy", "monetary system", "流动性"],
            isRecommended: true
        ),
        XBloggerPreset(
            id: "bill-ackman", name: "Bill Ackman", username: "BillAckman",
            category: .investment, role: "集中投资、公司治理与公开观点",
            topics: ["activist investing", "governance", "portfolio", "Pershing Square", "公司治理"],
            isRecommended: false
        ),
        XBloggerPreset(
            id: "morgan-housel", name: "Morgan Housel", username: "morganhousel",
            category: .investment, role: "投资心理、长期主义与财富行为",
            topics: ["investing psychology", "long term", "wealth", "behavior", "投资心理"],
            isRecommended: false
        )
    ]
}
