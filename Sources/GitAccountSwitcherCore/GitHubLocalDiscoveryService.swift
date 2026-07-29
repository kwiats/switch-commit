import Foundation

public struct GitHubLocalDiscoveryService {
    private let homeDirectory: URL
    private let commandRunner: CommandRunning
    private let fileManager: FileManager
    private let hostsParser: GitHubCLIHostsParser
    private let remoteParser: GitRemoteParser
    private let accountMerger: DetectedAccountMerger

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        commandRunner: CommandRunning = ProcessCommandRunner(),
        fileManager: FileManager = .default,
        hostsParser: GitHubCLIHostsParser = GitHubCLIHostsParser(),
        remoteParser: GitRemoteParser = GitRemoteParser(),
        accountMerger: DetectedAccountMerger = DetectedAccountMerger()
    ) {
        self.homeDirectory = homeDirectory
        self.commandRunner = commandRunner
        self.fileManager = fileManager
        self.hostsParser = hostsParser
        self.remoteParser = remoteParser
        self.accountMerger = accountMerger
    }

    public func detect(existingProfiles: [GitProfile]) -> [DetectedGitAccount] {
        accountMerger.merge(signals: automaticSignals(), existingProfiles: existingProfiles)
    }

    public func detect(in folderURL: URL, existingProfiles: [GitProfile]) -> [DetectedGitAccount] {
        accountMerger.merge(
            signals: automaticSignals() + repositoryRemoteSignals(in: folderURL),
            existingProfiles: existingProfiles
        )
    }

    public func automaticSignals() -> [DetectionSignal] {
        var signals = hostsFileSignals()
        signals += globalGitConfigSignals()
        signals += credentialUsernameSignals()
        signals += githubCLIInstallationSignals()
        signals += sshConfigurationSignals()
        return signals
    }

    public func repositoryRemoteSignals(in folderURL: URL) -> [DetectionSignal] {
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var signals: [DetectionSignal] = []
        for case let fileURL as URL in enumerator {
            guard let validatedConfigURL = validatedGitConfigURL(fileURL, within: folderURL),
                  let content = try? String(contentsOf: validatedConfigURL, encoding: .utf8)
            else {
                continue
            }

            for remoteURL in remoteURLs(in: content) {
                if let signal = remoteParser.signal(from: remoteURL) {
                    signals.append(signal)
                }
            }
        }
        return signals
    }

    private func hostsFileSignals() -> [DetectionSignal] {
        let hostsURL = homeDirectory.appendingPathComponent(".config/gh/hosts.yml")
        guard let content = try? String(contentsOf: hostsURL, encoding: .utf8) else {
            return []
        }
        return hostsParser.signals(from: content)
    }

    private func globalGitConfigSignals() -> [DetectionSignal] {
        let userName = commandOutput(for: ["config", "--global", "--get", "user.name"])
        let userEmail = commandOutput(for: ["config", "--global", "--get", "user.email"])
        guard userName != nil || userEmail != nil else {
            return []
        }
        return [
            DetectionSignal(
                provider: .github,
                gitUserName: userName,
                gitUserEmail: userEmail,
                confidence: .low,
                source: .globalGitConfig
            )
        ]
    }

    private func credentialUsernameSignals() -> [DetectionSignal] {
        let keys = [
            "credential.https://github.com.username",
            "credential.github.com.username"
        ]
        return keys.compactMap { key in
            guard let username = commandOutput(for: ["config", "--global", "--get", key]) else {
                return nil
            }
            return DetectionSignal(
                provider: .github,
                username: username,
                confidence: .medium,
                source: .gitCredentialUsername
            )
        }
    }

    private func githubCLIInstallationSignals() -> [DetectionSignal] {
        guard commandOutput(command: "gh", arguments: ["--version"]) != nil else {
            return []
        }
        return [
            DetectionSignal(
                provider: .github,
                confidence: .low,
                source: .githubCliInstalled
            )
        ]
    }

    private func sshConfigurationSignals() -> [DetectionSignal] {
        var signals = sshConfigFileSignals()
        if !signals.isEmpty,
           let resolvedConfig = commandOutput(command: "ssh", arguments: ["-G", "github.com"]),
           let identityFile = identityFile(in: resolvedConfig) {
            signals.append(
                DetectionSignal(
                    provider: .github,
                    sshKeyPath: identityFile,
                    confidence: .medium,
                    source: .sshResolvedConfig
                )
            )
        }
        return signals
    }

    private func sshConfigFileSignals() -> [DetectionSignal] {
        let sshDirectory = homeDirectory.appendingPathComponent(".ssh", isDirectory: true)
        let urls = [
            sshDirectory.appendingPathComponent("config"),
            sshDirectory.appendingPathComponent("git-account-switcher.conf")
        ]
        return urls.compactMap { url in
            guard let content = try? String(contentsOf: url, encoding: .utf8),
                  content.range(of: "github.com", options: .caseInsensitive) != nil
            else {
                return nil
            }
            return DetectionSignal(
                provider: .github,
                confidence: .low,
                source: .sshConfig
            )
        }
    }

    private func commandOutput(for arguments: [String]) -> String? {
        commandOutput(command: "git", arguments: arguments)
    }

    private func commandOutput(command: String, arguments: [String]) -> String? {
        guard let result = try? commandRunner.run(command, arguments: arguments, workingDirectory: nil),
              result.exitCode == 0
        else {
            return nil
        }
        let output = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    private func identityFile(in resolvedConfig: String) -> String? {
        for line in resolvedConfig.split(whereSeparator: \.isNewline) {
            let fields = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            if fields.count == 2, fields[0].lowercased() == "identityfile" {
                let path = String(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                return path.isEmpty ? nil : path
            }
        }
        return nil
    }

    private func isGitConfig(_ url: URL) -> Bool {
        url.lastPathComponent == "config" && url.deletingLastPathComponent().lastPathComponent == ".git"
    }

    private func validatedGitConfigURL(_ url: URL, within selectedRoot: URL) -> URL? {
        guard isGitConfig(url) else {
            return nil
        }

        let resolvedRoot = selectedRoot.resolvingSymlinksInPath().standardizedFileURL
        let resolvedConfig = url.resolvingSymlinksInPath().standardizedFileURL
        guard isGitConfig(resolvedConfig),
              isDescendant(resolvedConfig, of: resolvedRoot),
              let values = try? resolvedConfig.resourceValues(forKeys: [.isRegularFileKey]),
              values.isRegularFile == true
        else {
            return nil
        }
        return resolvedConfig
    }

    private func isDescendant(_ url: URL, of root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let components = url.pathComponents
        return components.count > rootComponents.count && components.starts(with: rootComponents)
    }

    private func remoteURLs(in config: String) -> [String] {
        config.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("url") else {
                return nil
            }
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespacesAndNewlines) == "url"
            else {
                return nil
            }
            let remoteURL = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            return remoteURL.isEmpty ? nil : remoteURL
        }
    }
}
