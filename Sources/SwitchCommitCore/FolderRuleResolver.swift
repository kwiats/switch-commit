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

public enum FolderRuleResolver {
    public static func resolve(
        path: String,
        rules: [FolderRule],
        profiles: [GitProfile],
        activeProfileId: String?
    ) -> FolderRuleResolution {
        let normalizedPath = FolderPathNormalizer.normalize(path)
        let candidates = rules.filter(\.enabled).compactMap { rule -> (FolderRule, Int)? in
            let rulePath = FolderPathNormalizer.normalize(rule.path)
            guard matches(path: normalizedPath, rulePath: rulePath, mode: rule.matchMode) else {
                return nil
            }
            return (rule, rulePath.count)
        }
        if let best = candidates.max(by: { $0.1 < $1.1 }) {
            let profile = profiles.first { $0.id == best.0.profileId }
            return FolderRuleResolution(kind: .folderRule, rule: best.0, profile: profile)
        }
        let active = profiles.first { $0.id == activeProfileId }
        return FolderRuleResolution(kind: .global, rule: nil, profile: active)
    }

    private static func matches(path: String, rulePath: String, mode: FolderRuleMatchMode) -> Bool {
        switch mode {
        case .singleRepo:
            return path == rulePath
        case .folderTree:
            return path == rulePath || path.hasPrefix(rulePath + "/")
        }
    }
}
