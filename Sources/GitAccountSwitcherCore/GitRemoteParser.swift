import Foundation

public struct GitRemoteParser: Sendable {
    public init() {}

    public func githubRemote(from remoteURL: String) -> GitHubRemoteAccount? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("git@github.com:") {
            return parsePath(String(trimmed.dropFirst("git@github.com:".count)))
        }
        if trimmed.hasPrefix("https://github.com/") {
            return parsePath(String(trimmed.dropFirst("https://github.com/".count)))
        }
        if trimmed.hasPrefix("ssh://git@github.com/") {
            return parsePath(String(trimmed.dropFirst("ssh://git@github.com/".count)))
        }
        return nil
    }

    public func signal(from remoteURL: String) -> DetectionSignal? {
        guard let remote = githubRemote(from: remoteURL) else {
            return nil
        }
        return DetectionSignal(
            provider: .github,
            username: nil,
            hosts: ["github.com"],
            confidence: .medium,
            source: .repositoryRemote,
            warnings: ["Remote owner '\(remote.owner)' may be a user or an organization."]
        )
    }

    private func parsePath(_ path: String) -> GitHubRemoteAccount? {
        let cleaned = path.hasSuffix(".git") ? String(path.dropLast(4)) : path
        guard !cleaned.contains("?"), !cleaned.contains("#") else {
            return nil
        }
        let parts = cleaned.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return nil
        }
        return GitHubRemoteAccount(owner: parts[0], repository: parts[1])
    }
}
