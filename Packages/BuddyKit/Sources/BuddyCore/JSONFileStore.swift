import Foundation

/// Reads and writes one Codable value as a JSON file in Application Support.
/// Writes are atomic, so a crash mid-save can't leave a half-written file.
public struct JSONFileStore<Value: Codable>: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `~/Library/Application Support/<folder>/<name>.json`
    /// (inside the app's container when sandboxed).
    public init(name: String, folder: String = "DesktopBuddy") throws {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let directory = support.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.url = directory.appendingPathComponent("\(name).json")
    }

    /// Returns nil when nothing has been saved yet.
    public func load() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(Value.self, from: data)
    }

    public func save(_ value: Value) throws {
        let data = try Self.encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }

    public func delete() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
