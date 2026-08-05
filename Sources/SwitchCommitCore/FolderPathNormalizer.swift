import Foundation

public enum FolderPathNormalizer {
    public static func normalize(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded: String
        if trimmed == "~" {
            expanded = FileManager.default.homeDirectoryForCurrentUser.path
        } else if trimmed.hasPrefix("~/") || trimmed.hasPrefix("~\\") {
            expanded = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(trimmed.dropFirst(2))).path
        } else {
            expanded = trimmed
        }
        if expanded.count > 1, expanded.hasSuffix("/") {
            return String(expanded.dropLast())
        }
        return expanded
    }
}
