import Foundation

public struct GitHubCLIHostsParser: Sendable {
    public init() {}

    public func signals(from content: String) -> [DetectionSignal] {
        let lines = content.split(whereSeparator: \.isNewline).map(String.init)
        var insideGitHub = false
        var username: String?
        var sawGitHubHost = false

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasSuffix(":") && !rawLine.hasPrefix(" ") && !rawLine.hasPrefix("\t") {
                insideGitHub = trimmed == "github.com:"
                sawGitHubHost = insideGitHub || sawGitHubHost
                continue
            }

            guard insideGitHub else {
                continue
            }

            if let value = value(for: "user", in: trimmed) {
                username = value
            } else if let value = value(for: "username", in: trimmed) {
                username = value
            }
        }

        guard sawGitHubHost else {
            return []
        }

        if let username, !username.isEmpty {
            return [
                DetectionSignal(
                    provider: .github,
                    username: username,
                    confidence: .high,
                    source: .githubCliHostsFile
                )
            ]
        }

        return [
            DetectionSignal(
                provider: .github,
                confidence: .medium,
                source: .githubCliHostsFile,
                warnings: ["GitHub CLI host is configured without a visible username."]
            )
        ]
    }

    private func value(for key: String, in line: String) -> String? {
        let prefix = "\(key):"
        guard line.hasPrefix(prefix) else {
            return nil
        }
        let value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
}
