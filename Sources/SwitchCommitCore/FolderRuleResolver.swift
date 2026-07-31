import Foundation

public enum FolderRuleResolver: Sendable {
    public static func normalize(_ path: String, homeDirectory: URL) -> String {
        var trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" {
            trimmed = homeDirectory.path
        } else if trimmed.hasPrefix("~/") {
            trimmed = homeDirectory.appendingPathComponent(String(trimmed.dropFirst(2))).path
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

            switch rule.matchMode {
            case .folderTree:
                return normalizedPath == normalizedRulePath
                    || normalizedPath.hasPrefix(normalizedRulePath + "/")
            case .singleRepo:
                return normalizedPath == normalizedRulePath
            }
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
}
