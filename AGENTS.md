# TrackAI Agent Guide

## 项目概览

- 原生 macOS SwiftUI App，Swift Package 名为 `SignalDesk`，成品名为 `TrackAI.app`。
- 目标是追踪 AI、机器人和投资领域关键人物的播客、采访、演讲、视频及持仓变化。
- 数据保存在本机；API Key 只能存入 macOS 钥匙串，禁止写入源码、日志或提交记录。

## 关键文件

- `Sources/SignalDesk/ContentView.swift`：主界面、筛选和详情交互。
- `Sources/SignalDesk/SignalStore.swift`：状态持久化、刷新和数据迁移。
- `Sources/SignalDesk/FeedClient.swift`：RSS/Atom、媒体检索、分类和评分。
- `Sources/SignalDesk/PersonCatalog.swift`：内置人物及来源。
- `Sources/SignalDesk/AISummaryService.swift`：Apple、Ollama、DeepSeek 总结。
- `Sources/SignalDesk/SEC13FClient.swift`：13F 解析及两期差分。
- `Sources/SignalDesk/InvestorHoldings.swift`：投资者预设、持仓模型和收益计算。
- `Sources/SignalDesk/InvestorHoldingsClient.swift`：SEC 历史、OpenFIGI、Twelve Data 与本地缓存。
- `Sources/SignalDesk/InvestorHoldingsView.swift`：投资者列表和持仓详情。
- `Tests/SignalDeskTests/`：对应功能测试。

## 产品约束

- 长内容来源优先，不要默认扩展 X 或不稳定的网页爬虫。
- 打开详情应标记已读；AI 总结只能由用户点击按钮后触发。
- “本机优先”不得自动调用 DeepSeek 等云端服务。
- 固定使用四个一级主题：模型与 Agent、机器人与具身智能、算力与芯片、投资与商业。
- 修改持久化模型或分类规则时，保留现有用户数据并补迁移测试。
- 13F 属于延迟披露，不得表述为实时持仓。
- 13F 不含真实买入价；成本和盈亏必须标注为估算，数据不足时显示不可用。
- 证券年化收益率使用复权行情，不得冒充投资者组合回报。

## 开发与验证

```bash
swift test
swift run
./scripts/build-app.sh
```

- 提交前运行 `swift test` 和 `git diff --check`。
- 正式 App 必须通过 `scripts/build-app.sh` 使用稳定 Apple 签名构建；禁止退回 ad-hoc 签名。
- 不提交 `.build/`、`dist/`、本地状态或任何凭据。
- 保持改动小而明确；新增行为应同步增加或更新测试。
