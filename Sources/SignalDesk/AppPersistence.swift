import Foundation

struct SignalStatePersistence {
    let url: URL

    init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL
    }

    func load() throws -> AppSnapshot {
        let data = try Data(contentsOf: url)
        return try JSONDecoder.signalDesk.decode(AppSnapshot.self, from: data)
    }

    func save(_ snapshot: AppSnapshot) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.signalDesk.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    private static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "SignalDesk", directoryHint: .isDirectory)
            .appending(path: "state.json")
    }
}

extension JSONEncoder {
    static var signalDesk: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var signalDesk: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
