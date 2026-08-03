import Combine
import Foundation
import UserNotifications

@MainActor
final class SignalStore: ObservableObject {
    @Published private(set) var sources: [TrackedSource] = []
    @Published private(set) var events: [SignalEvent] = []
    @Published private(set) var lastRefreshAt: Date?
    @Published var isRefreshing = false
    @Published var statusMessage: String?

    private let client = FeedClient()
    private let stateURL: URL
    private var installedCatalogIDs = Set<String>()
    private static let requestedPeopleCatalogID = "ai-robotics-longform-v4"
    private static let rayDalioCatalogID = "ray-dalio-v1"
    private static let domainTaxonomyID = "signal-domains-v3"

    init(stateURL: URL? = nil) {
        self.stateURL = stateURL ?? Self.defaultStateURL
        load()
        installRequestedPeopleIfNeeded()
        installRayDalioIfNeeded()
        installDomainTaxonomyIfNeeded()
    }

    var unreadCount: Int { events.filter { !$0.isRead }.count }
    var highValueCount: Int { events.filter { $0.importance >= 75 }.count }

    func add(_ source: TrackedSource) {
        sources.append(source)
        save()
    }

    @discardableResult
    func importPeople(_ people: [PersonPreset]) -> Int {
        var keys = Set(sources.map(Self.sourceKey))
        var added = 0

        for source in people.flatMap({ $0.trackedSources() }) {
            guard keys.insert(Self.sourceKey(source)).inserted else { continue }
            sources.append(source)
            added += 1
        }
        statusMessage = added == 0
            ? "这些人物已经在监控列表中"
            : "已导入 \(people.count) 位人物的 \(added) 个来源"
        save()
        return added
    }

    func enableXSources() {
        var changed = false
        for index in sources.indices where sources[index].sourceKind == .x && !sources[index].isEnabled {
            sources[index].isEnabled = true
            changed = true
        }
        if changed { save() }
    }

    func removeSources(at offsets: IndexSet) {
        let ids = offsets.map { sources[$0].id }
        sources.remove(atOffsets: offsets)
        events.removeAll { ids.contains($0.sourceID) }
        save()
    }

    func toggleSource(_ source: TrackedSource) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index].isEnabled.toggle()
        save()
    }

    func markRead(_ id: String) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        events[index].isRead = true
        save()
    }

    func toggleBookmark(_ id: String) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        events[index].isBookmarked.toggle()
        save()
    }

    func saveSummary(_ summary: AISummary, for id: String) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        events[index].aiSummary = summary
        save()
    }

    func clearSummary(for id: String) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        events[index].aiSummary = nil
        save()
    }

    func markAllRead() {
        for index in events.indices { events[index].isRead = true }
        save()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        statusMessage = nil
        defer { isRefreshing = false }

        var added: [SignalEvent] = []
        var failures: [String] = []
        let enabledSources = sources.filter(\.isEnabled)
        let batchesBrightDataX = XProvider.selected == .brightData
        let brightDataXSources = batchesBrightDataX
            ? enabledSources.filter { $0.sourceKind == .x }
            : []

        if !brightDataXSources.isEmpty {
            do {
                let incomingBySource = try await client.fetchX(brightDataXSources)
                let existingIDs = Set(events.map(\.id))
                for source in brightDataXSources {
                    let incoming = incomingBySource[source.id] ?? []
                    added.append(contentsOf: incoming.filter { !existingIDs.contains($0.id) })
                    if let index = sources.firstIndex(where: { $0.id == source.id }) {
                        sources[index].lastCheckedAt = Date()
                    }
                }
            } catch {
                failures.append(contentsOf: brightDataXSources.map {
                    "\($0.name)：\(error.localizedDescription)"
                })
            }
        }

        for source in enabledSources where !(batchesBrightDataX && source.sourceKind == .x) {
            if source.sourceKind == .mediaSearch,
               let lastCheckedAt = source.lastCheckedAt,
               Date().timeIntervalSince(lastCheckedAt) < 6 * 60 * 60 {
                continue
            }
            do {
                let incoming = try await client.fetch(source)
                let existingIDs = Set(events.map(\.id))
                added.append(contentsOf: incoming.filter { !existingIDs.contains($0.id) })
                if let index = sources.firstIndex(where: { $0.id == source.id }) {
                    sources[index].lastCheckedAt = Date()
                }
            } catch {
                failures.append("\(source.name)：\(error.localizedDescription)")
            }
        }

        events.append(contentsOf: added)
        events.sort { $0.publishedAt > $1.publishedAt }
        if events.count > 600 { events = Array(events.prefix(600)) }
        lastRefreshAt = Date()

        if failures.isEmpty {
            statusMessage = added.isEmpty ? "已是最新" : "新增 \(added.count) 条信号"
        } else {
            statusMessage = "新增 \(added.count) 条；\(failures.count) 个来源失败"
        }
        save()
        await notify(for: added.filter { $0.importance >= 80 })
    }

    private func load() {
        do {
            let data = try Data(contentsOf: stateURL)
            let snapshot = try JSONDecoder.signalDesk.decode(AppSnapshot.self, from: data)
            sources = snapshot.sources
            events = Array(snapshot.events.sorted { $0.publishedAt > $1.publishedAt }.prefix(600))
            lastRefreshAt = snapshot.lastRefreshAt
            installedCatalogIDs = Set(snapshot.installedCatalogIDs ?? [])
        } catch {
            sources = TrackedSource.starterSources
            events = Self.welcomeEvents(for: sources)
            save()
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: stateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let snapshot = AppSnapshot(
                sources: sources,
                events: events,
                lastRefreshAt: lastRefreshAt,
                installedCatalogIDs: Array(installedCatalogIDs).sorted()
            )
            let data = try JSONEncoder.signalDesk.encode(snapshot)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            statusMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func notify(for newEvents: [SignalEvent]) async {
        guard !newEvents.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "SignalDesk 捕捉到高价值信号"
        content.body = newEvents.count == 1
            ? newEvents[0].title
            : "\(newEvents[0].title) 等 \(newEvents.count) 条"
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private static var defaultStateURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "SignalDesk", directoryHint: .isDirectory)
            .appending(path: "state.json")
    }

    private static func welcomeEvents(for sources: [TrackedSource]) -> [SignalEvent] {
        guard let first = sources.first else { return [] }
        return [
            SignalEvent(
                id: "welcome",
                sourceID: first.id,
                sourceName: "SignalDesk",
                title: "你的高价值人物情报台已就绪",
                summary: "点击右上角刷新可拉取官方 RSS。添加 SEC 13F 来源时只需填写机构 CIK；所有数据默认保存在本机。",
                url: nil,
                publishedAt: Date(),
                category: .activity,
                importance: 92,
                matchedTopics: ["AI", "投资"],
                domains: []
            )
        ]
    }

    private func installRequestedPeopleIfNeeded() {
        guard installedCatalogIDs.insert(Self.requestedPeopleCatalogID).inserted else { return }

        let removedSourceIDs = sources
            .filter {
                ($0.sourceKind == .x &&
                 PersonPreset.legacyXUsernames.contains($0.feedURL.lowercased())) ||
                $0.sourceKind == .mediaSearch
            }
            .map(\.id)
        sources.removeAll { removedSourceIDs.contains($0.id) }
        events.removeAll { removedSourceIDs.contains($0.sourceID) }

        var keys = Set(sources.map(Self.sourceKey))
        var added = 0

        for source in PersonPreset.aiRoboticsLeaders.flatMap({ $0.trackedSources() }) {
            guard keys.insert(Self.sourceKey(source)).inserted else { continue }
            sources.append(source)
            added += 1
        }
        statusMessage = "已切换长内容追踪：移除 \(removedSourceIDs.count) 个 X 来源，新增 \(added) 个媒体来源"
        save()
    }

    private static func sourceKey(_ source: TrackedSource) -> String {
        "\(source.sourceKind.rawValue)|\(source.feedURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private func installRayDalioIfNeeded() {
        guard installedCatalogIDs.insert(Self.rayDalioCatalogID).inserted,
              let rayDalio = PersonPreset.aiRoboticsLeaders.first(where: { $0.id == "ray-dalio" }) else {
            return
        }

        var keys = Set(sources.map(Self.sourceKey))
        var added = 0
        for source in rayDalio.trackedSources() {
            guard keys.insert(Self.sourceKey(source)).inserted else { continue }
            sources.append(source)
            added += 1
        }
        if added > 0 {
            statusMessage = "已新增瑞·达利欧的 \(added) 个情报来源"
        }
        save()
    }

    private func installDomainTaxonomyIfNeeded() {
        guard installedCatalogIDs.insert(Self.domainTaxonomyID).inserted else { return }
        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        for index in events.indices {
            let event = events[index]
            let source = sourcesByID[event.sourceID]
            let text = "\(event.title) \(event.summary)"
            events[index].domains = SignalDomainClassifier.classify(
                text: text,
                fallbackDomains: source.map(PersonPreset.defaultDomains) ?? [],
                kind: source?.sourceKind
            )
        }
        save()
    }
}

private extension JSONEncoder {
    static var signalDesk: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var signalDesk: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
