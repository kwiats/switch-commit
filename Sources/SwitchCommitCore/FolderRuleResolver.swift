import Foundation

public struct FolderRuleResolution: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case folderRule
        case global
    }

    public var kind: Kind
    public var rule: FolderRule?
    public var profile: GitProfile?

    public init(kind: Kind, rule: FolderRule?, profile: GitProfile?) {
        self.kind = kind
        self.rule = rule
        self.profile = profile
    }
}

public enum FolderRuleResolver: Sendable {
    public static func normalize(
        _ path: String,
        homeDirectory: URL,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> String {
        var trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" {
            trimmed = homeDirectory.path
        } else if trimmed.hasPrefix("~/") || trimmed.hasPrefix("~\\") {
            trimmed = homeDirectory.appendingPathComponent(String(trimmed.dropFirst(2))).path
        } else if !(trimmed as NSString).isAbsolutePath {
            trimmed = currentDirectory.appendingPathComponent(trimmed).path
        }

        let standardized = (trimmed as NSString).standardizingPath
        guard standardized != "/" else {
            return "/"
        }
        return standardized.hasSuffix("/") ? String(standardized.dropLast()) : standardized
    }

    public static func match(
        path: String,
        rules: [FolderRule],
        homeDirectory: URL
    ) -> FolderRule? {
        let normalizedPath = normalize(path, homeDirectory: homeDirectory)

        let matches = rules.filter { rule in
            guard rule.enabled else { return false }
            let normalizedRulePath = normalize(rule.path, homeDirectory: homeDirectory)
            return Self.matches(path: normalizedPath, rulePath: normalizedRulePath, mode: rule.matchMode)
        }

        return matches.max { lhs, rhs in
            let lhsPath = normalize(lhs.path, homeDirectory: homeDirectory)
            let rhsPath = normalize(rhs.path, homeDirectory: homeDirectory)
            if lhsPath.count != rhsPath.count {
                return lhsPath.count < rhsPath.count
            }
            return lhsPath > rhsPath
        }
    }

    public static func resolve(
        path: String,
        rules: [FolderRule],
        profiles: [GitProfile],
        activeProfileId: String?
    ) -> FolderRuleResolution {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        if let rule = match(path: path, rules: rules, homeDirectory: homeDirectory) {
            let profile = profiles.first { $0.id == rule.profileId }
            return FolderRuleResolution(kind: .folderRule, rule: rule, profile: profile)
        }
        let active = profiles.first { $0.id == activeProfileId }
        return FolderRuleResolution(kind: .global, rule: nil, profile: active)
    }

    public static func pathMatches(_ path: String, rulePath: String, mode: FolderRuleMatchMode) -> Bool {
        matches(path: path, rulePath: rulePath, mode: mode)
    }

    private static func matches(path: String, rulePath: String, mode: FolderRuleMatchMode) -> Bool {
        switch mode {
        case .singleRepo:
            return path == rulePath
        case .folderTree:
            return ManagedPath.isEqualOrDescendantPath(path, of: rulePath)
        }
    }
}
