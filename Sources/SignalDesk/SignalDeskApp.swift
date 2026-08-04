import SwiftUI

@main
struct SignalDeskApp: App {
    @StateObject private var store = SignalStore()
    @StateObject private var investorStore = InvestorHoldingsStore()
    @StateObject private var investorWritingStore = InvestorWritingStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(investorStore)
                .environmentObject(investorWritingStore)
                .frame(minWidth: 1_040, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("刷新全部") {
                    Task { await store.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandGroup(replacing: .appSettings) {
                Button("设置") {
                    NotificationCenter.default.post(name: .signalDeskOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let signalDeskOpenSettings = Notification.Name("SignalDesk.openSettings")
}
