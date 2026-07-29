import Foundation

public struct GitConfigGenerator: Sendable {
    public init() {}

    public func profileConfig(for profile: GitProfile) -> String {
        """
        [user]
            name = \(escape(profile.gitUserName))
            email = \(escape(profile.gitUserEmail))
        [core]
            sshCommand = ssh -i \(escape(profile.sshKeyPath)) -F ~/.ssh/config

        """
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
}
