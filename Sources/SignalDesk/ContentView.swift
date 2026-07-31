import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: SignalStore
    @EnvironmentObject private var investorStore: InvestorHoldingsStore
    @Environment(\.openURL) private var openURL
    @State private var section: AppSection? = .inbox
    @State private var selection: String?
    @State private var showingAddSource = false
    @State private var query = ""
    @State private var category: SignalCategory?
    @State private var selectedTopic: SignalDomain?
    @State private var selectedInvestorID = InvestorPreset.featured.first?.id

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            if section == .sources {
                SourcesView(showingAddSource: $showingAddSource)
            } else if section == .investors {
                InvestorListView(selection: $selectedInvestorID)
            } else if section == .settings {
                SettingsView()
            } else {
                timeline
            }
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingAddSource) {
            AddSourceView()
        }
        .task {
            await store.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(900))
                guard !Task.isCancelled else { break }
                await store.refresh()
            }
        }
    }

    private var sidebar: some View {
        List(selection: $section) {
            Section {
                brand
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 16, leading: 10, bottom: 20, trailing: 8))
            }

            Section("监控") {
                ForEach(AppSection.allCases) { item in
                    Label {
                        HStack {
                            Text(item.title)
                            Spacer()
                            if let count = badgeCount(for: item), count > 0 {
                                Text("\(count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: item.icon)
                            .foregroundStyle(item == .highValue ? .orange : .blue)
                    }
                    .tag(item)
                }
            }

            Section("主题") {
                ForEach(SignalDomain.allCases) { domain in
                    topicRow(domain)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 210, ideal: 235, max: 280)
        .safeAreaInset(edge: .bottom) {
            Button {
                showingAddSource = true
            } label: {
                Label("添加监控对象", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.ultraThinMaterial)
        }
    }

    private var brand: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(LinearGradient(colors: [.indigo, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text("SignalDesk")
                    .font(.title3.weight(.bold))
                Text("重要人物情报台")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if filteredEvents.isEmpty {
                ContentUnavailableView(
                    "暂无匹配信号",
                    systemImage: "waveform.path.ecg",
                    description: Text("添加来源或调整筛选条件后刷新。")
                )
            } else {
                List(filteredEvents, selection: $selection) { event in
                    EventRow(event: event)
                        .tag(event.id)
                        .contextMenu {
                            Button(event.isBookmarked ? "取消收藏" : "收藏") {
                                store.toggleBookmark(event.id)
                            }
                            if let rawURL = event.url, let url = URL(string: rawURL) {
                                Button("打开原文") { openURL(url) }
                            }
                        }
                }
                .listStyle(.inset)
            }
        }
        .navigationSplitViewColumnWidth(min: 420, ideal: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedTopic.map { "\($0.title)主题" } ?? section?.title ?? "情报流")
                        .font(.largeTitle.weight(.bold))
                    Text(refreshSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let selectedTopic {
                    Button {
                        self.selectedTopic = nil
                        selection = nil
                    } label: {
                        Label("清除 \(selectedTopic.title)筛选", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer()
                if let message = store.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label(store.isRefreshing ? "刷新中" : "刷新", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshing)
                Button("全部已读") { store.markAllRead() }
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索人物、观点或关键词", text: $query)
                    .textFieldStyle(.plain)
                Divider().frame(height: 18)
                Picker("类型", selection: $category) {
                    Text("全部类型").tag(SignalCategory?.none)
                    ForEach(SignalCategory.allCases) { item in
                        Text(item.title).tag(Optional(item))
                    }
                }
                .labelsHidden()
                .frame(width: 110)
            }
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
        }
        .padding(20)
    }

    @ViewBuilder
    private var detail: some View {
        if section == .investors {
            InvestorPortfolioView(investorID: selectedInvestorID)
        } else if let event = selectedEvent {
            EventDetail(event: event)
                .onChange(of: event.id, initial: true) { _, eventID in
                    store.markRead(eventID)
                }
        } else {
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                ContentUnavailableView(
                    "选择一条信号",
                    systemImage: "scope",
                    description: Text("查看摘要、价值评分与原始来源。")
                )
            }
        }
    }

    private var selectedEvent: SignalEvent? {
        guard let selection else { return nil }
        return store.events.first { $0.id == selection }
    }

    private var filteredEvents: [SignalEvent] {
        store.events.filter { event in
            let sectionMatches: Bool
            switch section {
            case .highValue: sectionMatches = event.importance >= 75
            case .bookmarks: sectionMatches = event.isBookmarked
            default: sectionMatches = true
            }
            let categoryMatches = category == nil || event.category == category
            let topicMatches = selectedTopic.map { event.domains?.contains($0) == true } ?? true
            let queryMatches = query.isEmpty ||
                "\(event.sourceName) \(event.title) \(event.summary) \(event.matchedTopics.joined(separator: " "))"
                .localizedCaseInsensitiveContains(query)
            return sectionMatches && categoryMatches && topicMatches && queryMatches
        }
    }

    private var refreshSubtitle: String {
        if let date = store.lastRefreshAt {
            return "上次刷新 \(date.formatted(date: .omitted, time: .shortened)) · \(store.sources.filter(\.isEnabled).count) 个活跃来源"
        }
        return "\(store.sources.filter(\.isEnabled).count) 个活跃来源"
    }

    private func badgeCount(for item: AppSection) -> Int? {
        switch item {
        case .inbox: store.unreadCount
        case .highValue: store.highValueCount
        case .bookmarks: store.events.filter(\.isBookmarked).count
        case .investors: InvestorPreset.featured.count
        case .sources: store.sources.count
        case .settings: nil
        }
    }

    private func topicRow(_ domain: SignalDomain) -> some View {
        Button {
            selectedTopic = selectedTopic == domain ? nil : domain
            section = .inbox
            selection = nil
        } label: {
            HStack {
                Circle().fill(topicColor(domain)).frame(width: 7, height: 7)
                Text(domain.title)
                Spacer()
                Text("\(store.events.filter { $0.domains?.contains(domain) == true }.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                if selectedTopic == domain {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(topicColor(domain))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            selectedTopic == domain ? topicColor(domain).opacity(0.12) : Color.clear
        )
    }

    private func topicColor(_ domain: SignalDomain) -> Color {
        switch domain {
        case .modelsAgents: .purple
        case .robotics: .cyan
        case .compute: .blue
        case .investmentBusiness: .green
        }
    }
}

private struct EventRow: View {
    let event: SignalEvent

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Circle()
                .fill(event.isRead ? Color.clear : Color.blue)
                .frame(width: 7, height: 7)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(event.sourceName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Label(event.category.title, systemImage: event.category.icon)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(categoryColor)
                    Spacer()
                    Text(event.publishedAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(event.title)
                    .font(.headline)
                    .lineLimit(2)
                if !event.summary.isEmpty {
                    Text(event.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    ScorePill(score: event.importance)
                    ForEach(event.matchedTopics.prefix(3), id: \.self) { topic in
                        Text(topic)
                            .font(.caption2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                    Spacer()
                    if event.isBookmarked {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var categoryColor: Color {
        switch event.category {
        case .viewpoint: .purple
        case .activity: .blue
        case .holding: .green
        }
    }
}

private struct ScorePill: View {
    let score: Int

    var body: some View {
        Text("\(score) 分")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        score >= 80 ? .orange : (score >= 60 ? .blue : .secondary)
    }
}

private struct EventDetail: View {
    @EnvironmentObject private var store: SignalStore
    @Environment(\.openURL) private var openURL
    @State private var isSummarizing = false
    @State private var summaryError: String?
    let event: SignalEvent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Label(event.category.title, systemImage: event.category.icon)
                        .foregroundStyle(.blue)
                    Spacer()
                    Button {
                        store.toggleBookmark(event.id)
                    } label: {
                        Image(systemName: event.isBookmarked ? "bookmark.fill" : "bookmark")
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(event.title)
                        .font(.title.weight(.bold))
                        .textSelection(.enabled)
                    Text("\(event.sourceName) · \(event.publishedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 14) {
                    metric(title: "价值评分", value: "\(event.importance)", color: .orange)
                    metric(title: "命中主题", value: "\(event.matchedTopics.count)", color: .purple)
                }

                if !event.matchedTopics.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("命中主题").font(.headline)
                        HStack {
                            ForEach(event.matchedTopics, id: \.self) { topic in
                                Text(topic)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(.blue.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("来源摘要").font(.headline)
                    Text(event.summary.isEmpty ? "该来源未提供摘要，请打开原文查看。" : event.summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("AI 情报总结", systemImage: "sparkles")
                            .font(.headline)
                        Spacer()
                        if let summary = event.aiSummary {
                            Text(summary.provider.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("重新生成") {
                                store.clearSummary(for: event.id)
                                Task { await generateSummary() }
                            }
                            .font(.caption)
                            .disabled(isSummarizing)
                        }
                    }

                    if let summary = event.aiSummary {
                        Text(summary.content)
                            .font(.body)
                            .lineSpacing(6)
                            .textSelection(.enabled)
                        Text("生成于 \(summary.generatedAt.formatted(date: .abbreviated, time: .shortened)) · AI 内容可能有误，请结合原始来源核验")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else if isSummarizing {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("正在抓取正文并生成中文总结…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let summaryError {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(summaryError, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                            Button("重试") {
                                Task { await generateSummary() }
                            }
                        }
                    } else {
                        Button {
                            Task { await generateSummary() }
                        } label: {
                            Label("生成 AI 总结", systemImage: "sparkles")
                        }
                    }
                }
                .padding(16)
                .background(.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                if let rawURL = event.url, let url = URL(string: rawURL) {
                    Button {
                        openURL(url)
                    } label: {
                        Label("打开原始来源", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Spacer()
            }
            .padding(28)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @MainActor
    private func generateSummary() async {
        guard !isSummarizing else { return }
        isSummarizing = true
        summaryError = nil
        defer { isSummarizing = false }

        do {
            let summary = try await AISummaryService().summarize(event)
            store.saveSummary(summary, for: event.id)
        } catch {
            summaryError = error.localizedDescription
        }
    }

    private func metric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}
