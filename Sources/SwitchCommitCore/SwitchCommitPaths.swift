import Foundation

public enum SwitchCommitPaths: Sendable {
    public static func defaultProfilesURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("git-account-switcher", isDirectory: true)
            .appendingPathComponent("profiles.json")
    }
}
