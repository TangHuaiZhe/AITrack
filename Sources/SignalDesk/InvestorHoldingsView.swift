import AppKit
import SwiftUI

private enum InvestorDetailTab: String, CaseIterable, Identifiable {
    case holdings
    case writings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .holdings: "持仓"
        case .writings: "观点与信件"
        }
    }
}

struct InvestorListView: View {
    @EnvironmentObject private var store: InvestorHoldingsStore
    @Binding var selection: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("杰出投资者")
                    .font(.largeTitle.weight(.bold))
                Text("季度持仓、基金信与投资观点")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Divider()

            List(InvestorPreset.featured, selection: $selection) { investor in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(investor.name)
                            .font(.headline)
                        Spacer()
                        if let portfolio = store.portfolio(for: investor.id) {
                            Text(portfolio.reportDate)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(investor.firm)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(investor.style)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(.vertical, 7)
                .tag(investor.id)
            }
            .listStyle(.inset)
        }
        .navigationSplitViewColumnWidth(min: 270, ideal: 320, max: 380)
    }
}

struct InvestorPortfolioView: View {
    @EnvironmentObject private var store: InvestorHoldingsStore
    @EnvironmentObject private var writingStore: InvestorWritingStore
    @State private var selectedTab = InvestorDetailTab.holdings
    @State private var selectedWritingID: String?
    let investorID: String?

    private var investor: InvestorPreset? {
        InvestorPreset.featured.first { $0.id == investorID }
    }

    var body: some View {
        if let investor {
            VStack(spacing: 0) {
                portfolioHeader(investor)
                Divider()
                if selectedTab == .holdings {
                    portfolioContent(investor)
                } else {
                    writingsContent(investor)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: investorID) {
                selectedWritingID = writingStore.writings(for: investor.id).first?.id
            }
        } else {
            ContentUnavailableView(
                "选择一位投资者",
                systemImage: "chart.pie",
                description: Text("查看最近一期 13F 持仓和长期收益指标。")
            )
        }
    }

    private func portfolioHeader(_ investor: InvestorPreset) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(investor.name)
                        .font(.largeTitle.weight(.bold))
                    Text("\(investor.firm) · \(investor.style)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedTab == .holdings {
                    Button {
                        Task { await store.refresh(investor) }
                    } label: {
                        Label(
                            store.refreshingInvestorID == investor.id ? "刷新中" : "刷新持仓",
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.refreshingInvestorID != nil)
                } else {
                    Button {
                        Task { await writingStore.refresh(investor) }
                    } label: {
                        Label(
                            writingStore.refreshingInvestorID == investor.id ? "刷新中" : "刷新观点",
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(writingStore.refreshingInvestorID != nil)
                }
            }

            Picker("查看内容", selection: $selectedTab) {
                ForEach(InvestorDetailTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)

            if selectedTab == .holdings {
                HStack(spacing: 8) {
                    Label("SEC EDGAR", systemImage: "building.columns")
                    Text("季度末快照，最长可能滞后约 45 天")
                    if let portfolio = store.portfolio(for: investor.id) {
                        Text("·")
                        Text("报告期 \(portfolio.reportDate)")
                        Text("·")
                        Text("申报 \(portfolio.filingDate)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if store.refreshingInvestorID == investor.id {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(
                            value: store.totalMarketSymbols > 0
                                ? Double(store.completedMarketSymbols)
                                : nil,
                            total: store.totalMarketSymbols > 0
                                ? Double(store.totalMarketSymbols)
                                : 1
                        )
                        Text(store.statusMessage ?? "正在更新…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if store.statusInvestorID == investor.id,
                          let message = store.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.hasPrefix("刷新失败") ? .red : .secondary)
                }
            } else {
                HStack(spacing: 8) {
                    Label("官方原文优先", systemImage: "checkmark.seal")
                    Text("区分本人署名与基金团队材料；AI 仅在点击后解析")
                    if let archive = InvestorWritingCatalog.archiveURL(for: investor.id) {
                        Link("官方档案", destination: archive)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if writingStore.statusInvestorID == investor.id,
                   let message = writingStore.statusMessage {
                    Text(message)
                    .font(.caption)
                    .foregroundStyle(message.hasPrefix("观点刷新失败") ? .red : .secondary)
                }
            }
        }
        .padding(22)
    }

    @ViewBuilder
    private func portfolioContent(_ investor: InvestorPreset) -> some View {
        if let portfolio = store.portfolio(for: investor.id) {
            VStack(spacing: 0) {
                portfolioSummary(portfolio)
                Divider()
                holdingsTable(portfolio)
                metricFootnote
            }
        } else {
            ContentUnavailableView {
                Label("尚未读取持仓", systemImage: "tray")
            } description: {
                Text("SEC 13F 无需 API Key；先读取申报即可查看持仓和占比。")
            } actions: {
                Button("读取最新 13F") {
                    Task { await store.refresh(investor) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.refreshingInvestorID != nil)
            }
        }
    }

    private func portfolioSummary(_ portfolio: InvestorPortfolio) -> some View {
        HStack(spacing: 26) {
            summaryMetric("申报总值", usd(portfolio.totalValueUSD))
            summaryMetric("持仓数量", "\(portfolio.positions.count)")
            summaryMetric(
                "已补全行情",
                "\(portfolio.positions.filter { $0.latestPrice != nil }.count)"
            )
            Spacer()
            Text("更新于 \(portfolio.refreshedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private func writingsContent(_ investor: InvestorPreset) -> some View {
        let writings = writingStore.writings(for: investor.id)
        if writings.isEmpty {
            ContentUnavailableView {
                Label("暂无稳定公开基金信", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("这不代表投资者没有观点；只是目前没有可稳定核验、可公开访问的本人或基金官方信件来源。")
            } actions: {
                Button("检查官方来源") {
                    Task { await writingStore.refresh(investor) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(writingStore.refreshingInvestorID != nil)
            }
        } else {
            HSplitView {
                List(writings, selection: $selectedWritingID) { writing in
                    WritingRow(writing: writing)
                        .tag(writing.id)
                }
                .listStyle(.inset)
                .frame(minWidth: 270, idealWidth: 330, maxWidth: 390)

                if let writing = selectedWriting(in: writings) {
                    InvestorWritingDetail(writing: writing)
                        .id(writing.id)
                } else {
                    ContentUnavailableView(
                        "选择一份材料",
                        systemImage: "doc.text",
                        description: Text("查看署名、原始来源，并按需生成 AI 总结。")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                if selectedWriting(in: writings) == nil {
                    selectedWritingID = writings.first?.id
                }
            }
        }
    }

    private func selectedWriting(in writings: [InvestorWriting]) -> InvestorWriting? {
        guard let selectedWritingID else { return nil }
        return writings.first { $0.id == selectedWritingID }
    }

    private func holdingsTable(_ portfolio: InvestorPortfolio) -> some View {
        Table(portfolio.positions) {
            TableColumn("持仓") { position in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(position.ticker ?? position.cusip)
                            .font(.headline.monospaced())
                        if let putCall = position.putCall {
                            Text(putCall.uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(position.issuer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                        .contextMenu {
                            Button("复制公司名") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(
                                    position.issuer,
                                    forType: .string
                                )
                            }
                        }
                }
            }
            .width(min: 180, ideal: 250)

            TableColumn("占比") { position in
                numericText(percent(position.portfolioWeight))
            }
            .width(min: 55, ideal: 65, max: 75)

            TableColumn("股数") { position in
                numericText(shares(position.shares))
            }
            .width(min: 70, ideal: 85, max: 100)

            TableColumn("申报价值") { position in
                numericText(usd(position.valueUSD))
            }
            .width(min: 78, ideal: 92, max: 110)

            TableColumn("估算成本") { position in
                VStack(alignment: .trailing, spacing: 2) {
                    Text(position.estimatedCost.map(currency) ?? "—")
                        .monospacedDigit()
                    if let confidence = position.costConfidence {
                        Text(confidence.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 82, ideal: 96, max: 110)

            TableColumn("估算盈亏") { position in
                returnText(position.estimatedProfitLoss)
            }
            .width(min: 70, ideal: 80, max: 90)

            TableColumn("1 年") { position in
                returnText(position.returns.oneYear)
            }
            .width(min: 55, ideal: 65, max: 75)

            TableColumn("3 年") { position in
                returnText(position.returns.threeYears)
            }
            .width(min: 55, ideal: 65, max: 75)

            TableColumn("5 年") { position in
                returnText(position.returns.fiveYears)
            }
            .width(min: 55, ideal: 65, max: 75)

            TableColumn("10 年") { position in
                returnText(position.returns.tenYears)
            }
            .width(min: 55, ideal: 65, max: 75)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var metricFootnote: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("估算成本：历史股数先按拆股追溯调整，再按过去约 5 年季度增仓量和当期价格加权；减仓不重置成本。")
            Text("估算盈亏及 1/3/5/10 年 CAGR 使用拆股复权价格，不含股息；期权、无法映射或历史不足时显示“—”。")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35))
    }

    private func summaryMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func numericText(_ text: String) -> some View {
        Text(text)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func returnText(_ value: Double?) -> some View {
        Text(value.map(percent) ?? "—")
            .fontWeight(value.map { abs($0) >= 0.2 } == true ? .semibold : .regular)
            .foregroundStyle(returnColor(value))
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func returnColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        if value > 0 { return .green }
        if value < 0 { return .red }
        return .primary
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(1)))
    }

    private func currency(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    private func usd(_ value: Int64) -> String {
        if value >= 1_000_000_000 {
            return "$" + (Double(value) / 1_000_000_000).formatted(
                .number.precision(.fractionLength(1))
            ) + "B"
        }
        if value >= 1_000_000 {
            return "$" + (Double(value) / 1_000_000).formatted(
                .number.precision(.fractionLength(1))
            ) + "M"
        }
        return "$" + value.formatted(.number)
    }

    private func shares(_ value: Double) -> String {
        value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }
}

private struct WritingRow: View {
    let writing: InvestorWriting

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(writing.kind.title, systemImage: writing.kind.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                Spacer()
                Text(writing.displaysYearOnly == true
                    ? writing.period ?? writing.publishedAt.formatted(.dateTime.year())
                    : writing.publishedAt.formatted(.dateTime.year().month().day()))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text(writing.title)
                .font(.headline)
                .lineLimit(3)
            HStack(spacing: 6) {
                Text(writing.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(writing.attribution.title)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        writing.attribution == .namedAuthor
                            ? Color.green.opacity(0.12)
                            : Color.orange.opacity(0.12),
                        in: Capsule()
                    )
                Spacer()
                if writing.aiSummary != nil {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.purple)
                }
            }
        }
        .padding(.vertical, 7)
    }
}

private struct InvestorWritingDetail: View {
    @EnvironmentObject private var store: InvestorWritingStore
    @Environment(\.openURL) private var openURL
    @State private var isSummarizing = false
    @State private var summaryError: String?
    let writing: InvestorWriting

    private var currentWriting: InvestorWriting {
        store.writing(id: writing.id, investorID: writing.investorID) ?? writing
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Label(currentWriting.kind.title, systemImage: currentWriting.kind.icon)
                        .foregroundStyle(.blue)
                    Text(currentWriting.attribution.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(attributionColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(attributionColor)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text(currentWriting.title)
                        .font(.title2.weight(.bold))
                        .textSelection(.enabled)
                    Text("\(currentWriting.author) · \(currentWriting.publisher)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if let period = currentWriting.period {
                        Text(
                            currentWriting.displaysYearOnly == true
                                ? "报告年份 \(period)"
                                : "报告期 \(period) · "
                                    + currentWriting.publishedAt.formatted(
                                        date: .abbreviated,
                                        time: .omitted
                                    )
                        )
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text(
                            currentWriting.publishedAt.formatted(
                                date: .abbreviated,
                                time: .omitted
                            )
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("来源归属")
                        .font(.headline)
                    Text(currentWriting.sourceNote)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("AI 投资分析", systemImage: "sparkles")
                            .font(.headline)
                        Spacer()
                        if let summary = currentWriting.aiSummary {
                            Text(summary.provider.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("重新生成") {
                                store.clearSummary(
                                    writingID: currentWriting.id,
                                    investorID: currentWriting.investorID
                                )
                                Task { await generateSummary() }
                            }
                            .font(.caption)
                            .disabled(isSummarizing)
                        }
                    }

                    if let summary = currentWriting.aiSummary {
                        MarkdownText(summary.content)
                            .lineSpacing(6)
                            .textSelection(.enabled)
                        Text(
                            "生成于 \(summary.generatedAt.formatted(date: .abbreviated, time: .shortened))"
                                + " · AI 内容可能有误，请结合原文和 13F 核验"
                        )
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    } else if isSummarizing {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("正在读取原文并分析投资观点…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let summaryError {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(summaryError, systemImage: "exclamationmark.triangle.fill")
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

                Button {
                    if let url = URL(string: currentWriting.sourceURL) {
                        openURL(url)
                    }
                } label: {
                    Label("打开官方原文", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var attributionColor: Color {
        currentWriting.attribution == .namedAuthor ? .green : .orange
    }

    @MainActor
    private func generateSummary() async {
        guard !isSummarizing else { return }
        isSummarizing = true
        summaryError = nil
        defer { isSummarizing = false }

        do {
            let summary = try await AISummaryService().summarize(currentWriting)
            store.saveSummary(
                summary,
                writingID: currentWriting.id,
                investorID: currentWriting.investorID
            )
        } catch {
            summaryError = error.localizedDescription
        }
    }
}
