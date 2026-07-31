import Foundation

public struct SSHKeyDiscovery: Sendable {
    private let homeDirectory: URL

    private static let excludedExactNames: Set<String> = [
        "config",
        "known_hosts",
        "authorized_keys",
        "git-account-switcher.conf"
    ]

    private static let excludedPrefixes = [
        "config.",
        "known_hosts.",
        "authorized_keys."
    ]

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    public func discoverKeyPaths() -> [String] {
        var candidates = Set<String>()
        candidates.formUnion(directoryPrivateKeyPaths())
        candidates.formUnion(identityFilePaths(named: "config"))
        candidates.formUnion(identityFilePaths(named: "git-account-switcher.conf"))

        return candidates.sorted { lhs, rhs in
            let leftName = URL(fileURLWithPath: expandHome(lhs)).lastPathComponent
            let rightName = URL(fileURLWithPath: expandHome(rhs)).lastPathComponent
            if leftName != rightName {
                return leftName.localizedStandardCompare(rightName) == .orderedAscending
            }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    private func directoryPrivateKeyPaths() -> Set<String> {
        let sshDirectory = homeDirectory.appendingPathComponent(".ssh", isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: sshDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var paths = Set<String>()
        for url in contents {
            guard isIncludedPrivateKeyFile(url) else { continue }
            paths.insert(displayPath(for: url))
        }
        return paths
    }

    private func identityFilePaths(named fileName: String) -> Set<String> {
        let configURL = homeDirectory
            .appendingPathComponent(".ssh", isDirectory: true)
            .appendingPathComponent(fileName)
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return []
        }

        var paths = Set<String>()
        for line in content.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let fields = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard fields.count == 2, fields[0].lowercased() == "identityfile" else { continue }
            let raw = String(fields[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard !raw.isEmpty else { continue }
            let expanded = expandHome(raw)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else {
                continue
            }
            paths.insert(displayPath(for: URL(fileURLWithPath: expanded)))
        }
        return paths
    }

    private func isIncludedPrivateKeyFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasSuffix(".pub") { return false }
        if Self.excludedExactNames.contains(name) { return false }
        if Self.excludedPrefixes.contains(where: { name.hasPrefix($0) }) { return false }

        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
        guard values?.isDirectory != true, values?.isRegularFile == true else {
            return false
        }
        return true
    }

    private func displayPath(for url: URL) -> String {
        let standardized = url.standardizedFileURL.path
        let homePath = homeDirectory.standardizedFileURL.path
        if standardized == homePath || standardized.hasPrefix(homePath + "/") {
            let suffix = String(standardized.dropFirst(homePath.count))
            return "~" + suffix
        }
        return standardized
    }

    private func expandHome(_ path: String) -> String {
        if path == "~" {
            return homeDirectory.path
        }
        if path.hasPrefix("~/") {
            return URL(fileURLWithPath: String(path.dropFirst(2)), relativeTo: homeDirectory)
                .standardizedFileURL
                .path
        }
        return path
    }
}
