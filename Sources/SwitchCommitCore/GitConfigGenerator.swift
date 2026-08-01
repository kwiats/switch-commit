import Foundation

public struct GitConfigGenerator: Sendable {
    public init() {}

    public func profileConfig(for profile: GitProfile) -> String {
        var sections: [String] = [
            """
            [user]
                name = \(escape(profile.gitUserName))
                email = \(escape(profile.gitUserEmail))
            """
        ]

        if profile.accessMethod == .ssh {
            sections.append(
                """
                [core]
                    sshCommand = ssh -i \(shellQuote(profile.sshKeyPath))
                """
            )
        }

        let rewrite = urlRewriteSections(for: profile)
        if !rewrite.isEmpty {
            sections.append(contentsOf: rewrite)
        }

        return sections.joined(separator: "\n") + "\n"
    }

    public func rootIncludeConfig(globalConfigPath: String, rulesConfigPath: String) -> String {
        """
        [include]
            path = \(escape(globalConfigPath))
            path = \(escape(rulesConfigPath))

        """
    }

    public func rulesConfig(rules: [FolderRule], profilesDirectory: String) -> String {
        rules
            .filter(\.enabled)
            .map { rule in
                let gitdir = gitdirPattern(for: rule)
                return """
                [includeIf "gitdir:\(escape(gitdir))"]
                    path = \(escape(profilesDirectory))/\(escape(rule.profileId)).gitconfig

                """
            }
            .joined()
    }

    private func urlRewriteSections(for profile: GitProfile) -> [String] {
        profile.hosts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { host in
                let escapedHost = escape(host)
                switch profile.accessMethod {
                case .ssh:
                    return """
                    [url "git@\(escapedHost):"]
                        insteadOf = https://\(escapedHost)/
                        insteadOf = ssh://git@\(escapedHost)/
                    """
                case .https:
                    return """
                    [url "https://\(escapedHost)/"]
                        insteadOf = git@\(escapedHost):
                        insteadOf = ssh://git@\(escapedHost)/
                    """
                }
            }
    }

    private func gitdirPattern(for rule: FolderRule) -> String {
        switch rule.matchMode {
        case .folderTree:
            return rule.path.hasSuffix("/") ? "\(rule.path)**" : "\(rule.path)/**"
        case .singleRepo:
            return rule.path.hasSuffix("/") ? rule.path : "\(rule.path)/"
        }
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
