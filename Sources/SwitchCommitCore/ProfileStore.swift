import Foundation

public struct ProfileStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> ProfileStoreData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ProfileStoreData()
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(ProfileStoreData.self, from: data)
    }

    public func save(_ storeData: ProfileStoreData) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(storeData)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic])
    }
}
