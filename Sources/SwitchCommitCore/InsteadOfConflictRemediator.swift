import Foundation

public struct InsteadOfEntry: Equatable, Sendable {
    public var originPath: String
    public var key: String
    public var value: String

    public init(originPath: String, key: String, value: String) {
        self.originPath = originPath
        self.key = key
        self.value = value
    }
}

public struct InsteadOfConflictRemediator {
    public struct Result: Equatable, Sendable {
        public var removed: [InsteadOfEntry]
        public var remainingConflicts: [InsteadOfEntry]

        public init(removed: [InsteadOfEntry] = [], remainingConflicts: [InsteadOfEntry] = []) {
            self.removed = removed
            self.remainingConflicts = remainingConflicts
        }
    }

    private let managedDirectoryPath: String
    private let fileManager: FileManager

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.managedDirectoryPath = homeDirectory
            .appendingPathComponent(".config/git-account-switcher", isDirectory: true)
            .standardizedFileURL
            .path
        self.fileManager = fileManager
    }

    public func conflictingEntries(
        entries: [InsteadOfEntry],
        activeProfile: GitProfile?
    ) -> [InsteadOfEntry] {
        guard let activeProfile else {
            return []
        }
        let hosts = Set(
            activeProfile.hosts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        guard !hosts.isEmpty else {
            return []
        }

        return entries.filter { entry in
            guard isUnmanaged(originPath: entry.originPath) else {
                return false
            }
            return conflicts(with: activeProfile.accessMethod, hosts: hosts, entry: entry)
        }
    }

    /// Removes conflicting unmanaged insteadOf keys from `~/.gitconfig` (with backup).
    public func remediate(
        entries: [InsteadOfEntry],
        activeProfile: GitProfile?,
        rootGitConfigURL: URL,
        backup: (URL) throws -> Void
    ) throws -> Result {
        let conflicts = conflictingEntries(entries: entries, activeProfile: activeProfile)
        guard !conflicts.isEmpty else {
            return Result()
        }

        let rootPath = rootGitConfigURL.standardizedFileURL.path
        let removable = conflicts.filter {
            URL(fileURLWithPath: $0.originPath).standardizedFileURL.path == rootPath
        }
        let remaining = conflicts.filter {
            URL(fileURLWithPath: $0.originPath).standardizedFileURL.path != rootPath
        }

        guard !removable.isEmpty else {
            return Result(remainingConflicts: remaining)
        }

        if fileManager.fileExists(atPath: rootGitConfigURL.path) {
            try backup(rootGitConfigURL)
        }

        var removed: [InsteadOfEntry] = []
        for entry in removable {
            try unset(key: entry.key, value: entry.value, in: rootGitConfigURL)
            removed.append(entry)
        }

        return Result(removed: removed, remainingConflicts: remaining)
    }

    public func parseRootGitConfig(_ content: String, originPath: String) -> [InsteadOfEntry] {
        var entries: [InsteadOfEntry] = []
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var currentURL: String?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentURL = nil
                if trimmed.lowercased().hasPrefix("[url ") {
                    let inner = trimmed.dropFirst(5).dropLast()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    currentURL = String(inner)
                }
                continue
            }
            guard let currentURL else {
                continue
            }
            guard trimmed.lowercased().hasPrefix("insteadof") else {
                continue
            }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2, parts[0].lowercased() == "insteadof" else {
                continue
            }
            entries.append(
                InsteadOfEntry(
                    originPath: originPath,
                    key: "url.\(currentURL).insteadof",
                    value: parts[1]
                )
            )
        }
        return entries
    }

    public func parseGitConfigShowOriginRegexp(output: String) -> [InsteadOfEntry] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> InsteadOfEntry? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("file:") else {
                    return nil
                }
                let withoutPrefix = trimmed.dropFirst("file:".count)
                guard let tabIndex = withoutPrefix.firstIndex(of: "\t") else {
                    return nil
                }
                let origin = String(withoutPrefix[..<tabIndex])
                let rest = withoutPrefix[withoutPrefix.index(after: tabIndex)...]
                    .trimmingCharacters(in: .whitespaces)
                let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard parts.count == 2 else {
                    return nil
                }
                return InsteadOfEntry(
                    originPath: origin,
                    key: String(parts[0]),
                    value: String(parts[1])
                )
            }
    }

    private func isUnmanaged(originPath: String) -> Bool {
        let path = URL(fileURLWithPath: originPath).standardizedFileURL.path
        return !path.hasPrefix(managedDirectoryPath)
    }

    private func conflicts(
        with accessMethod: GitAccessMethod,
        hosts: Set<String>,
        entry: InsteadOfEntry
    ) -> Bool {
        let key = entry.key.lowercased()
        let value = entry.value.lowercased()
        guard key.hasPrefix("url."), key.hasSuffix(".insteadof") else {
            return false
        }
        let urlKey = String(key.dropFirst(4).dropLast(".insteadof".count))

        switch accessMethod {
        case .ssh:
            // Unmanaged forces HTTPS (or similar) instead of SSH forms for our hosts.
            guard hosts.contains(where: { host in
                value.contains("git@\(host):")
                    || value.contains("ssh://git@\(host)/")
                    || value == "git@\(host):"
                    || value.hasPrefix("ssh://git@\(host)/")
            }) else {
                return false
            }
            return hosts.contains(where: { host in
                urlKey == "https://\(host)/" || urlKey.hasPrefix("https://\(host)/")
            })
        case .https:
            guard hosts.contains(where: { host in
                value.contains("https://\(host)/") || value.hasPrefix("https://\(host)/")
            }) else {
                return false
            }
            return hosts.contains(where: { host in
                urlKey == "git@\(host):"
                    || urlKey == "ssh://git@\(host)/"
                    || urlKey.hasPrefix("ssh://git@\(host)/")
            })
        }
    }

    private func unset(key: String, value: String, in fileURL: URL) throws {
        var content = ""
        if fileManager.fileExists(atPath: fileURL.path) {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        }
        let updated = removeInsteadOf(key: key, value: value, from: content)
        try updated.data(using: .utf8)?.write(to: fileURL, options: [.atomic])
    }

    /// Removes a single insteadOf assignment under the matching `[url "..."]` section.
    func removeInsteadOf(key: String, value: String, from content: String) -> String {
        // key form: url.https://github.com/.insteadof
        let lowerKey = key.lowercased()
        guard lowerKey.hasPrefix("url."), lowerKey.hasSuffix(".insteadof") else {
            return content
        }
        let sectionURL = String(key.dropFirst(4).dropLast(".insteadof".count))
        let sectionHeader = "[url \"\(sectionURL)\"]"
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var result: [String] = []
        var index = 0
        var removedAny = false

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces) == sectionHeader {
                result.append(line)
                index += 1
                var keptInSection: [String] = []
                while index < lines.count {
                    let body = lines[index]
                    let trimmed = body.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("[") {
                        break
                    }
                    if trimmed.lowercased().hasPrefix("insteadof") {
                        let assigned = trimmed.split(separator: "=", maxSplits: 1).map {
                            $0.trimmingCharacters(in: .whitespaces)
                        }
                        if assigned.count == 2,
                           assigned[0].lowercased() == "insteadof",
                           assigned[1] == value {
                            removedAny = true
                            index += 1
                            continue
                        }
                    }
                    keptInSection.append(body)
                    index += 1
                }
                let meaningful = keptInSection.contains {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                if meaningful || !removedAny {
                    result.append(contentsOf: keptInSection)
                } else {
                    // Drop empty section header we just added.
                    if result.last == line {
                        result.removeLast()
                    }
                }
                continue
            }
            result.append(line)
            index += 1
        }

        var text = result.joined(separator: "\n")
        if content.hasSuffix("\n"), !text.hasSuffix("\n") {
            text += "\n"
        }
        return text
    }
}
