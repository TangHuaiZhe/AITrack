import SwiftUI

struct SourcesView: View {
    @EnvironmentObject private var store: SignalStore
    @Binding var showingAddSource: Bool
    @State private var showingPeopleCatalog = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("监控对象")
                        .font(.largeTitle.weight(.bold))
                    Text("人物、机构及其公开信息源")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showingPeopleCatalog = true
                } label: {
                    Label("导入人物库", systemImage: "person.3.sequence.fill")
                }
                Button {
                    showingAddSource = true
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
            Divider()

            List {
                ForEach(store.sources) { source in
                    HStack(spacing: 13) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                            .fill(source.sourceKind == .sec13F ? Color.green.opacity(0.14) : Color.blue.opacity(0.14))
                            Text(source.initials)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(source.sourceKind == .sec13F ? .green : .blue)
                        }
                        .frame(width: 42, height: 42)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(source.name).font(.headline)
                            Text(source.role).font(.caption).foregroundStyle(.secondary)
                            Label(source.sourceKind.title, systemImage: source.sourceKind.icon)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { source.isEnabled },
                                    set: { _ in store.toggleSource(source) }
                                )
                            )
                            .labelsHidden()
                            if let date = source.lastCheckedAt {
                                Text(date, format: .relative(presentation: .named))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.vertical, 7)
                }
                .onDelete(perform: store.removeSources)
            }
        }
        .sheet(isPresented: $showingPeopleCatalog) {
            PeopleCatalogView()
        }
    }
}

struct AddSourceView: View {
    @EnvironmentObject private var store: SignalStore
    @Environment(\.dismiss) private var dismiss
    @State private var kind: SourceKind = .rss
    @State private var name = ""
    @State private var role = ""
    @State private var topics = ""
    @State private var feedURL = ""
    @State private var cik = ""
    @State private var username = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("添加监控对象")
                    .font(.title2.weight(.bold))
                Text("连接公开 RSS / Atom，或监控机构的 SEC 13F 披露。")
                    .foregroundStyle(.secondary)
            }

            Picker("来源类型", selection: $kind) {
                ForEach(SourceKind.userAddableCases) { sourceKind in
                    Label(sourceKind.title, systemImage: sourceKind.icon).tag(sourceKind)
                }
            }
            .pickerStyle(.segmented)

            Form {
                TextField(kind == .rss ? "人物 / 机构名称" : "投资机构名称", text: $name)
                TextField("角色 / 关注原因", text: $role)
                if kind == .rss {
                    TextField("RSS / Atom 地址", text: $feedURL)
                    TextField("关注主题（逗号分隔）", text: $topics)
                } else if kind == .sec13F {
                    TextField("SEC CIK（只填数字）", text: $cik)
                    Text("示例：Berkshire Hathaway 的 CIK 为 1067983")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("X 用户名（不含 @ 也可以）", text: $username)
                    TextField("关注主题（逗号分隔）", text: $topics)
                    if KeychainStore.xBearerToken == nil {
                        Label("请先在设置中保存 X API Bearer Token", systemImage: "key")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)

            if kind == .sec13F {
                Label(
                    "13F 是季度披露，通常有时滞；本应用监控新申报，不把它误称为实时持仓。",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("添加并监控") {
                    add()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch kind {
        case .rss:
            return URL(string: feedURL)?.scheme?.hasPrefix("http") == true
        case .sec13F:
            return !cik.isEmpty && cik.allSatisfy(\.isNumber)
        case .x:
            return !username.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")).isEmpty
        case .mediaSearch:
            return false
        }
    }

    private func add() {
        let source: TrackedSource
        if kind == .sec13F {
            source = .sec13F(name: name, role: role.isEmpty ? "机构投资者" : role, cik: cik)
        } else if kind == .x {
            source = .x(
                name: name,
                role: role.isEmpty ? "X 公开观点" : role,
                username: username,
                topics: parsedTopics,
                isEnabled: KeychainStore.xBearerToken != nil
            )
        } else {
            source = TrackedSource(
                name: name,
                role: role.isEmpty ? "自定义来源" : role,
                topics: parsedTopics,
                sourceKind: .rss,
                feedURL: feedURL
            )
        }
        store.add(source)
        dismiss()
        Task { await store.refresh() }
    }

    private var parsedTopics: [String] {
        topics
            .split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: SignalStore
    @AppStorage(AISummaryService.modeDefaultsKey) private var summaryModeRaw = AISummaryMode.localFirst.rawValue
    @AppStorage(AISummaryService.ollamaModelDefaultsKey) private var ollamaModel = AISummaryService.defaultOllamaModel
    @State private var token = KeychainStore.xBearerToken ?? ""
    @State private var isRevealed = false
    @State private var isTesting = false
    @State private var status: String?
    @State private var statusIsError = false
    @State private var deepSeekKey = KeychainStore.deepSeekAPIKey ?? ""
    @State private var isDeepSeekRevealed = false
    @State private var isTestingDeepSeek = false
    @State private var deepSeekStatus: String?
    @State private var deepSeekStatusIsError = false
    @State private var ollamaStatus = "检测中…"
    @State private var isCheckingOllama = false
    @State private var twelveDataKey = KeychainStore.twelveDataAPIKey ?? ""
    @State private var isTwelveDataRevealed = false
    @State private var isTestingTwelveData = false
    @State private var twelveDataStatus: String?
    @State private var twelveDataStatusIsError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("设置")
                        .font(.largeTitle.weight(.bold))
                    Text("外部服务凭据只保存在这台 Mac 的钥匙串中")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("AI 总结", systemImage: "sparkles")
                            .font(.headline)
                        Text("只有点击详情页的“生成 AI 总结”后才会调用模型，结果会缓存。本机模型不产生 API 费用；视频与播客在没有字幕时仅根据标题和节目简介总结。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Picker("总结方式", selection: $summaryModeRaw) {
                            ForEach(AISummaryMode.allCases) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)

                        HStack(alignment: .firstTextBaseline) {
                            Label("Apple 本机模型", systemImage: "laptopcomputer")
                            Spacer()
                            Text(AISummaryService.localAvailabilityDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        Text("Ollama 免费本地模型")
                            .font(.subheadline.weight(.semibold))
                        Text("当前推荐 M4 / 16 GB 使用 qwen3.5:4b。模型约占数 GB 磁盘，生成时会使用本机算力，文章不会上传。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            TextField("Ollama 模型名称", text: $ollamaModel)
                                .textFieldStyle(.roundedBorder)
                            Button("检测") {
                                Task { await checkOllama() }
                            }
                            .disabled(isCheckingOllama)
                            Link(
                                "安装 Ollama",
                                destination: URL(string: "https://ollama.com/download/mac")!
                            )
                        }
                        HStack(spacing: 7) {
                            if isCheckingOllama {
                                ProgressView().controlSize(.small)
                            }
                            Text(ollamaStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("安装后运行：ollama run \(ollamaModel)")
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }

                        Divider()

                        Text("DeepSeek 备用")
                            .font(.subheadline.weight(.semibold))
                        Text("仅在你明确选择 DeepSeek 时调用，正文会发送给 DeepSeek。API Key 只保存在钥匙串。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Group {
                                if isDeepSeekRevealed {
                                    TextField("DeepSeek API Key（可选）", text: $deepSeekKey)
                                } else {
                                    SecureField("DeepSeek API Key（可选）", text: $deepSeekKey)
                                }
                            }
                            .textFieldStyle(.roundedBorder)

                            Button {
                                isDeepSeekRevealed.toggle()
                            } label: {
                                Image(systemName: isDeepSeekRevealed ? "eye.slash" : "eye")
                            }
                        }

                        HStack {
                            Button("保存到钥匙串") {
                                KeychainStore.deepSeekAPIKey = deepSeekKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                deepSeekStatus = deepSeekKey.isEmpty ? "已移除 API Key" : "API Key 已安全保存"
                                deepSeekStatusIsError = false
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isTestingDeepSeek)

                            Button("验证连接") {
                                Task { await validateDeepSeek() }
                            }
                            .disabled(deepSeekKey.isEmpty || isTestingDeepSeek)

                            if isTestingDeepSeek {
                                ProgressView().controlSize(.small)
                            }
                            if let deepSeekStatus {
                                Label(
                                    deepSeekStatus,
                                    systemImage: deepSeekStatusIsError ? "xmark.circle.fill" : "checkmark.circle.fill"
                                )
                                .font(.caption)
                                .foregroundStyle(deepSeekStatusIsError ? .red : .green)
                            }
                        }
                    }
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("X 官方 API", systemImage: "at")
                            .font(.headline)
                        Text("用于读取关键人物的公开 Posts。需要 X Developer Portal 中 App 的 Bearer Token。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack {
                            Group {
                                if isRevealed {
                                    TextField("Bearer Token", text: $token)
                                } else {
                                    SecureField("Bearer Token", text: $token)
                                }
                            }
                            .textFieldStyle(.roundedBorder)

                            Button {
                                isRevealed.toggle()
                            } label: {
                                Image(systemName: isRevealed ? "eye.slash" : "eye")
                            }
                        }

                        HStack {
                            Button("保存到钥匙串") {
                                KeychainStore.xBearerToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !token.isEmpty { store.enableXSources() }
                                status = token.isEmpty ? "已移除 Token" : "Token 已安全保存"
                                statusIsError = false
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isTesting)

                            Button("验证连接") {
                                Task { await validate() }
                            }
                            .disabled(token.isEmpty || isTesting)

                            if isTesting {
                                ProgressView().controlSize(.small)
                            }
                            if let status {
                                Label(status, systemImage: statusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(statusIsError ? .red : .green)
                            }
                        }
                    }
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("SEC EDGAR", systemImage: "building.columns")
                            .font(.headline)
                        Text("13F 数据直接读取 SEC 官方公开接口，无需 API Key。TrackAI 对最近两个报告期进行逐证券差分，并用约 5 年申报历史估算建仓成本。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Twelve Data 行情", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.headline)
                        Text("用于计算持仓的估算盈亏与 1/3/5/10 年拆股复权价格 CAGR。免费 Basic 计划限 8 credits/分钟、800 credits/天；TrackAI 会按 8 个标的一批自动等待并缓存结果。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack {
                            Group {
                                if isTwelveDataRevealed {
                                    TextField("Twelve Data API Key（可选）", text: $twelveDataKey)
                                } else {
                                    SecureField("Twelve Data API Key（可选）", text: $twelveDataKey)
                                }
                            }
                            .textFieldStyle(.roundedBorder)

                            Button {
                                isTwelveDataRevealed.toggle()
                            } label: {
                                Image(systemName: isTwelveDataRevealed ? "eye.slash" : "eye")
                            }
                        }

                        HStack {
                            Button("保存到钥匙串") {
                                let key = twelveDataKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                KeychainStore.twelveDataAPIKey = key
                                twelveDataStatus = key.isEmpty ? "已移除 API Key" : "API Key 已安全保存"
                                twelveDataStatusIsError = false
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isTestingTwelveData)

                            Button("验证连接") {
                                Task { await validateTwelveData() }
                            }
                            .disabled(twelveDataKey.isEmpty || isTestingTwelveData)

                            Link(
                                "获取免费 Key",
                                destination: URL(string: "https://twelvedata.com/pricing")!
                            )

                            if isTestingTwelveData {
                                ProgressView().controlSize(.small)
                            }
                            if let twelveDataStatus {
                                Label(
                                    twelveDataStatus,
                                    systemImage: twelveDataStatusIsError
                                        ? "xmark.circle.fill"
                                        : "checkmark.circle.fill"
                                )
                                .font(.caption)
                                .foregroundStyle(twelveDataStatusIsError ? .red : .green)
                            }
                        }
                    }
                    .padding(8)
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .task {
            await checkOllama()
        }
    }

    @MainActor
    private func validate() async {
        isTesting = true
        status = nil
        defer { isTesting = false }
        do {
            try await XClient().validateToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
            KeychainStore.xBearerToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
            store.enableXSources()
            status = "连接成功，Token 已保存"
            statusIsError = false
        } catch {
            status = error.localizedDescription
            statusIsError = true
        }
    }

    @MainActor
    private func validateDeepSeek() async {
        isTestingDeepSeek = true
        deepSeekStatus = nil
        defer { isTestingDeepSeek = false }
        let key = deepSeekKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await DeepSeekClient().validate(apiKey: key)
            KeychainStore.deepSeekAPIKey = key
            deepSeekStatus = "连接成功，API Key 已保存"
            deepSeekStatusIsError = false
        } catch {
            deepSeekStatus = error.localizedDescription
            deepSeekStatusIsError = true
        }
    }

    @MainActor
    private func validateTwelveData() async {
        isTestingTwelveData = true
        twelveDataStatus = nil
        defer { isTestingTwelveData = false }
        let key = twelveDataKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await TwelveDataClient().validate(apiKey: key)
            KeychainStore.twelveDataAPIKey = key
            twelveDataStatus = "连接成功，API Key 已保存"
            twelveDataStatusIsError = false
        } catch {
            twelveDataStatus = error.localizedDescription
            twelveDataStatusIsError = true
        }
    }

    @MainActor
    private func checkOllama() async {
        guard !isCheckingOllama else { return }
        isCheckingOllama = true
        defer { isCheckingOllama = false }
        do {
            let models = try await OllamaClient().installedModels()
            if models.isEmpty {
                ollamaStatus = "服务已启动，但还没有下载模型"
            } else if models.contains(where: { $0 == ollamaModel || $0.hasPrefix("\(ollamaModel):") }) {
                ollamaStatus = "\(ollamaModel) 已就绪"
            } else {
                ollamaStatus = "服务已启动；已安装：\(models.prefix(3).joined(separator: "、"))"
            }
        } catch {
            ollamaStatus = error.localizedDescription
        }
    }
}

struct PeopleCatalogView: View {
    @EnvironmentObject private var store: SignalStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set(PersonPreset.aiRoboticsLeaders.map(\.id))

    private let people = PersonPreset.aiRoboticsLeaders

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI / 机器人关键人物")
                            .font(.title2.weight(.bold))
                        Text("来自你提供的清单。每个来源均区分本人观点与机构输出。")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(selected.count == people.count ? "全部取消" : "全选") {
                        selected = selected.count == people.count ? [] : Set(people.map(\.id))
                    }
                }

                Label("不导入人物 X；重点追踪采访、播客、演讲、视频和官方长内容。", systemImage: "mic.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .padding(.top, 6)
            }
            .padding(22)

            Divider()

            List(people) { person in
                Button {
                    if selected.contains(person.id) {
                        selected.remove(person.id)
                    } else {
                        selected.insert(person.id)
                    }
                } label: {
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: selected.contains(person.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selected.contains(person.id) ? .blue : .secondary)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(person.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                sourceBadge("长内容检索", color: .blue)
                                ForEach(person.feeds, id: \.url) { feed in
                                    sourceBadge(feed.label, color: .purple)
                                }
                            }
                            Text(person.stance)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text("追踪：\(person.variables.prefix(5).joined(separator: " · "))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Text("已选择 \(selected.count) / \(people.count) 人")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }
                Button("导入并开始监控") {
                    let chosen = people.filter { selected.contains($0.id) }
                    store.importPeople(chosen)
                    dismiss()
                    Task { await store.refresh() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
            }
            .padding(18)
        }
        .frame(width: 760, height: 680)
    }

    private func sourceBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }
}
