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
        guard isAllowed(standardizedTarget),
              isAllowedResolvedLocation(standardizedTarget) else {
            throw SwitchCommitError.writeOutsideManagedRoots
        }

        try fileManager.createDirectory(
            at: standardizedTarget.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: standardizedTarget.path) {
            let existing = try? String(contentsOf: standardizedTarget, encoding: .utf8)
            if existing == content {
                return
            }
            try backupExistingFile(at: standardizedTarget)
        }

        try content.data(using: .utf8)?.write(to: standardizedTarget, options: [.atomic])
    }

    private func isAllowed(_ targetURL: URL) -> Bool {
        allowedRoots.contains { root in
            targetURL.path == root.path || targetURL.path.hasPrefix(root.path + "/")
        }
    }

    private func isAllowedResolvedLocation(_ targetURL: URL) -> Bool {
        let resolvedParent = targetURL
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let resolvedTarget = resolvedParent.appendingPathComponent(targetURL.lastPathComponent)
        return allowedRoots.contains { root in
            let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
            return resolvedTarget.path == resolvedRoot.path || resolvedTarget.path.hasPrefix(resolvedRoot.path + "/")
        }
    }

    private func backupExistingFile(at targetURL: URL) throws {
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        // UUID keeps concurrent CLI/app reapply backups from colliding on second-resolution timestamps.
        let backupURL = backupDirectory.appendingPathComponent(
            "\(timestamp)-\(UUID().uuidString)-\(targetURL.lastPathComponent)"
        )
        try fileManager.copyItem(at: targetURL, to: backupURL)
    }
}
