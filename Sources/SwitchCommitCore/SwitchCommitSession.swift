import Foundation

public enum ContextSource: String, Equatable, Sendable {
    case global
    case folder
    case none
}

public struct StatusSnapshot: Equatable, Sendable {
    public var activeProfile: GitProfile?
    public var contextProfile: GitProfile?
    public var contextPath: String?
    public var contextSource: ContextSource

    public init(
        activeProfile: GitProfile?,
        contextProfile: GitProfile?,
        contextPath: String?,
        contextSource: ContextSource
    ) {
        self.activeProfile = activeProfile
        self.contextProfile = contextProfile
        self.contextPath = contextPath
        self.contextSource = contextSource
    }
}

public final class SwitchCommitSession {
    private let manager: ProfileSettingsManager
    private let homeDirectory: URL
    private let diagnosticsService: DiagnosticsService

    public init(
        profileStore: ProfileStore,
        keychainStore: KeychainStoring,
        gitConfigInstaller: GitConfigInstalling?,
        homeDirectory: URL,
        commandRunner: CommandRunning = ProcessCommandRunner()
    ) throws {
        let standardizedHomeDirectory = homeDirectory.standardizedFileURL
        self.manager = try ProfileSettingsManager(
            profileStore: profileStore,
            keychainStore: keychainStore,
            seedProfiles: [],
            gitConfigInstaller: gitConfigInstaller,
            homeDirectory: standardizedHomeDirectory
        )
        self.homeDirectory = standardizedHomeDirectory
        self.diagnosticsService = DiagnosticsService(commandRunner: commandRunner)
    }

    public var profiles: [GitProfile] {
        manager.profiles
    }

    public var rules: [FolderRule] {
        manager.rules
    }

    public var activeProfile: GitProfile? {
        manager.activeProfile
    }

    public func use(reference: String) throws {
        try manager.switchGlobalProfile(to: show(reference: reference))
    }

    public func status(path: String?) -> StatusSnapshot {
        let inspectedPath = path ?? FileManager.default.currentDirectoryPath
        if let rule = FolderRuleResolver.match(
            path: inspectedPath,
            rules: rules,
            homeDirectory: homeDirectory
        ) {
            return StatusSnapshot(
                activeProfile: activeProfile,
                contextProfile: profiles.first { $0.id == rule.profileId },
                contextPath: inspectedPath,
                contextSource: .folder
            )
        }

        let source: ContextSource = activeProfile == nil ? .none : .global
        return StatusSnapshot(
            activeProfile: activeProfile,
            contextProfile: activeProfile,
            contextPath: inspectedPath,
            contextSource: source
        )
    }

    public func show(reference: String) throws -> GitProfile {
        try ProfileReferenceResolver.resolve(reference, in: profiles)
    }

    @discardableResult
    public func addProfile(
        displayName: String,
        gitUserName: String,
        gitUserEmail: String,
        accessMethod: GitAccessMethod,
        sshKeyPath: String,
        hosts: [String],
        httpsCredentialRef: String? = nil
    ) throws -> GitProfile {
        let profile = try GitProfile(
            id: "profile-\(UUID().uuidString.lowercased())",
            displayName: displayName,
            gitUserName: gitUserName,
            gitUserEmail: gitUserEmail,
            accessMethod: accessMethod,
            sshKeyPath: sshKeyPath,
            hosts: hosts,
            httpsCredentialRef: httpsCredentialRef,
            isDefault: activeProfile == nil
        )
        try manager.addProfile(profile)
        return try show(reference: profile.id)
    }

    @discardableResult
    public func editProfile(
        reference: String,
        displayName: String? = nil,
        gitUserName: String? = nil,
        gitUserEmail: String? = nil,
        accessMethod: GitAccessMethod? = nil,
        sshKeyPath: String? = nil,
        hosts: [String]? = nil,
        httpsCredentialRef: String?? = nil
    ) throws -> GitProfile {
        let current = try show(reference: reference)
        let updatedProfile = try GitProfile(
            id: current.id,
            displayName: displayName ?? current.displayName,
            gitUserName: gitUserName ?? current.gitUserName,
            gitUserEmail: gitUserEmail ?? current.gitUserEmail,
            accessMethod: accessMethod ?? current.accessMethod,
            sshKeyPath: sshKeyPath ?? current.sshKeyPath,
            hosts: hosts ?? current.hosts,
            httpsCredentialRef: httpsCredentialRef ?? current.httpsCredentialRef,
            isDefault: current.isDefault
        )
        try manager.updateProfile(updatedProfile)
        return try show(reference: updatedProfile.id)
    }

    public func deleteProfile(reference: String) throws {
        try manager.deleteProfile(id: show(reference: reference).id)
    }

    @discardableResult
    public func addFolderRule(
        path: String,
        profileReference: String,
        matchMode: FolderRuleMatchMode = .folderTree,
        moveIfOwned: Bool = false
    ) throws -> FolderRule {
        let profile = try show(reference: profileReference)
        return try manager.addFolderRule(
            path: path,
            profileId: profile.id,
            matchMode: matchMode,
            moveIfOwned: moveIfOwned
        )
    }

    public func removeFolderRule(id: String) throws {
        try manager.removeFolderRule(id: id)
    }

    public func removeFolderRule(path: String) throws {
        try manager.removeFolderRule(path: path)
    }

    public func doctor(path: String?) -> DiagnosticsReport {
        let inspectedPath = path ?? FileManager.default.currentDirectoryPath
        var report = diagnosticsService.inspectGitIdentity(at: URL(fileURLWithPath: inspectedPath))
        let snapshot = status(path: inspectedPath)
        if snapshot.contextSource == .folder,
           let active = snapshot.activeProfile,
           let context = snapshot.contextProfile,
           active.accessMethod != context.accessMethod {
            report.warnings.append(
                "Folder profile '\(context.displayName)' uses \(context.accessMethod.rawValue) while global profile '\(active.displayName)' uses \(active.accessMethod.rawValue); url.insteadOf access method rules from both profiles may conflict."
            )
        }
        return report
    }

    public static func live() throws -> SwitchCommitSession {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        return try SwitchCommitSession(
            profileStore: ProfileStore(fileURL: SwitchCommitPaths.defaultProfilesURL(homeDirectory: homeDirectory)),
            keychainStore: SystemKeychainStore(),
            gitConfigInstaller: ManagedGitConfigInstaller(homeDirectory: homeDirectory),
            homeDirectory: homeDirectory
        )
    }
}
