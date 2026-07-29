import Foundation

public struct SafeFileWriter {
    public let allowedRoots: [URL]
    public let backupDirectory: URL
    private let fileManager: FileManager

    public init(
        allowedRoots: [URL],
        backupDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.allowedRoots = allowedRoots.map { $0.standardizedFileURL }
        self.backupDirectory = backupDirectory.standardizedFileURL
        self.fileManager = fileManager
    }

    public func write(_ content: String, to targetURL: URL) throws {
        let standardizedTarget = targetURL.standardizedFileURL
        guard isAllowed(standardizedTarget) else {
            throw GitAccountSwitcherError.writeOutsideManagedRoots
        }

        try fileManager.createDirectory(
            at: standardizedTarget.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: standardizedTarget.path) {
            try backupExistingFile(at: standardizedTarget)
        }

        try content.data(using: .utf8)?.write(to: standardizedTarget, options: [.atomic])
    }

    private func isAllowed(_ targetURL: URL) -> Bool {
        allowedRoots.contains { root in
            targetURL.path == root.path || targetURL.path.hasPrefix(root.path + "/")
        }
    }

    private func backupExistingFile(at targetURL: URL) throws {
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = backupDirectory
            .appendingPathComponent("\(timestamp)-\(targetURL.lastPathComponent)")
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.copyItem(at: targetURL, to: backupURL)
    }
}
