import Foundation

public protocol GitConfigInstalling {
    func apply(profiles: [GitProfile], rules: [FolderRule], activeProfile: GitProfile?) throws
}

public struct ManagedGitConfigInstaller: GitConfigInstalling {
    private let homeDirectory: URL
    private let managedDirectory: URL
    private let profilesDirectory: URL
    private let backupsDirectory: URL
    private let fileManager: FileManager
    private let generator: GitConfigGenerator

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        generator: GitConfigGenerator = GitConfigGenerator()
    ) {
        let standardizedHome = homeDirectory.standardizedFileURL
        self.homeDirectory = standardizedHome
        self.managedDirectory = standardizedHome
            .appendingPathComponent(".config/git-account-switcher", isDirectory: true)
        self.profilesDirectory = managedDirectory
            .appendingPathComponent("profiles", isDirectory: true)
        self.backupsDirectory = managedDirectory
            .appendingPathComponent("backups", isDirectory: true)
        self.fileManager = fileManager
        self.generator = generator
    }

    public func apply(profiles: [GitProfile], rules: [FolderRule], activeProfile: GitProfile?) throws {
        let writer = SafeFileWriter(
            allowedRoots: [managedDirectory],
            backupDirectory: backupsDirectory,
            fileManager: fileManager
        )

        for profile in profiles {
            try writer.write(
                generator.profileConfig(for: profile),
                to: profilesDirectory.appendingPathComponent("\(profile.id).gitconfig")
            )
        }

        let globalConfig = activeProfile.map { generator.profileConfig(for: $0) } ?? ""
        try writer.write(globalConfig, to: managedDirectory.appendingPathComponent("global.gitconfig"))
        try writer.write(
            generator.rulesConfig(
                rules: rules,
                profilesDirectory: "~/.config/git-account-switcher/profiles"
            ),
            to: managedDirectory.appendingPathComponent("rules.gitconfig")
        )

        try ensureRootGitConfigIncludesManagedFiles()
        try remediateConflictingInsteadOf(activeProfile: activeProfile)
    }

    private func remediateConflictingInsteadOf(activeProfile: GitProfile?) throws {
        let remediator = InsteadOfConflictRemediator(
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )
        let rootGitConfigURL = homeDirectory.appendingPathComponent(".gitconfig")
        let content: String
        if fileManager.fileExists(atPath: rootGitConfigURL.path) {
            content = try String(contentsOf: rootGitConfigURL, encoding: .utf8)
        } else {
            content = ""
        }
        let entries = remediator.parseRootGitConfig(content, originPath: rootGitConfigURL.path)
        _ = try remediator.remediate(
            entries: entries,
            activeProfile: activeProfile,
            rootGitConfigURL: rootGitConfigURL,
            backup: backupExistingRootGitConfig(at:)
        )
    }

    private func ensureRootGitConfigIncludesManagedFiles() throws {
        let rootGitConfigURL = homeDirectory.appendingPathComponent(".gitconfig")
        let globalIncludePath = "~/.config/git-account-switcher/global.gitconfig"
        let rulesIncludePath = "~/.config/git-account-switcher/rules.gitconfig"
        let existingContent: String

        if fileManager.fileExists(atPath: rootGitConfigURL.path) {
            existingContent = try String(contentsOf: rootGitConfigURL, encoding: .utf8)
        } else {
            existingContent = ""
        }

        let missingPaths = [globalIncludePath, rulesIncludePath].filter { includePath in
            !existingContent.contains("path = \(includePath)")
        }
        guard !missingPaths.isEmpty else {
            return
        }

        let includeBlock = """
        [include]
        \(missingPaths.map { "    path = \($0)" }.joined(separator: "\n"))

        """
        let separator = existingContent.isEmpty || existingContent.hasSuffix("\n") ? "" : "\n"
        let updatedContent = existingContent + separator + includeBlock

        if fileManager.fileExists(atPath: rootGitConfigURL.path) {
            try backupExistingRootGitConfig(at: rootGitConfigURL)
        }

        try fileManager.createDirectory(
            at: rootGitConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try updatedContent.data(using: .utf8)?.write(to: rootGitConfigURL, options: [.atomic])
    }

    private func backupExistingRootGitConfig(at rootGitConfigURL: URL) throws {
        try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = backupsDirectory
            .appendingPathComponent("\(timestamp)-gitconfig")
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.copyItem(at: rootGitConfigURL, to: backupURL)
    }
}
