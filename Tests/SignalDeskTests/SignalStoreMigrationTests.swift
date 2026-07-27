import Foundation
import Testing
@testable import SignalDesk

struct SignalStoreMigrationTests {
    @Test @MainActor
    func installsRequestedPeopleOnlyOnce() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let stateURL = directory.appending(path: "state.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = SignalStore(stateURL: stateURL)
        let firstKeys = Set(first.sources.map { "\($0.sourceKind.rawValue)|\($0.feedURL.lowercased())" })
        let second = SignalStore(stateURL: stateURL)

        #expect(first.sources.count == 17)
        #expect(firstKeys.count == first.sources.count)
        #expect(first.sources.filter { $0.sourceKind == .x }.isEmpty)
        #expect(first.sources.filter { $0.sourceKind == .mediaSearch }.count == 11)
        #expect(second.sources.count == first.sources.count)
    }
}
