import SwiftUI

struct InvestorListView: View {
    @EnvironmentObject private var store: InvestorHoldingsStore
    @Binding var selection: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("杰出投资者")
                    .font(.largeTitle.weight(.bold))
                Text("基于 SEC 13F 的季度持仓，不是实时仓位")
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
    let investorID: String?

    private var investor: InvestorPreset? {
        InvestorPreset.featured.first { $0.id == investorID }
    }

    var body: some View {
        if let investor {
            VStack(spacing: 0) {
                portfolioHeader(investor)
                Divider()
                portfolioContent(investor)
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
            }

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
        }
        .padding(22)
    }

    @ViewBuilder
    private func portfolioContent(_ investor: InvestorPreset) -> some View {
        if let portfolio = store.portfolio(for: investor.id) {
            VStack(spacing: 0) {
                portfolioSummary(portfolio)
                Divider()
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(portfolio.positions) { position in
                                positionRow(position)
                                Divider()
                            }
                        } header: {
                            VStack(spacing: 0) {
                                columnHeader
                                Divider()
                            }
                            .background(.background)
                        }
                    }
                    .frame(minWidth: 800)
                }
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

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Text("持仓").frame(maxWidth: .infinity, alignment: .leading)
            column("占比", width: 62)
            column("估算成本", width: 86)
            column("估算盈亏", width: 82)
            column("1 年", width: 62)
            column("3 年", width: 62)
            column("5 年", width: 62)
            column("10 年", width: 62)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 22)
        .padding(.vertical, 9)
    }

    private func positionRow(_ position: InvestorPosition) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(position.ticker ?? position.cusip)
                        .font(.headline.monospaced())
                    if let putCall = position.putCall {
                        Text(putCall.uppercased())
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.14), in: Capsule())
                    }
                }
                Text(position.issuer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(shares(position.shares)) 股 · \(usd(position.valueUSD))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            metric(percent(position.portfolioWeight), width: 62)
            VStack(alignment: .trailing, spacing: 2) {
                Text(position.estimatedCost.map(currency) ?? "—")
                    .monospacedDigit()
                if let confidence = position.costConfidence {
                    Text(confidence.title)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 86, alignment: .trailing)
            returnMetric(position.estimatedProfitLoss, width: 82)
            returnMetric(position.returns.oneYear, width: 62)
            returnMetric(position.returns.threeYears, width: 62)
            returnMetric(position.returns.fiveYears, width: 62)
            returnMetric(position.returns.tenYears, width: 62)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 11)
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

    private func column(_ text: String, width: CGFloat) -> some View {
        Text(text).frame(width: width, alignment: .trailing)
    }

    private func metric(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .monospacedDigit()
            .frame(width: width, alignment: .trailing)
    }

    private func returnMetric(_ value: Double?, width: CGFloat) -> some View {
        Text(value.map(percent) ?? "—")
            .fontWeight(value.map { abs($0) >= 0.2 } == true ? .semibold : .regular)
            .foregroundStyle(returnColor(value))
            .monospacedDigit()
            .frame(width: width, alignment: .trailing)
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
