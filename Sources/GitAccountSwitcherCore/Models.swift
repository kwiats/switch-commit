import Foundation

public enum GitAccountSwitcherError: Error, Equatable {
    case emptyDisplayName
    case emptyGitUserName
    case emptyGitUserEmail
    case emptySSHKeyPath
    case emptyHost
    case emptyFolderRulePath
    case writeOutsideManagedRoots
}

public struct GitProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var displayName: String
    public var gitUserName: String
    public var gitUserEmail: String
    public var sshKeyPath: String
    public var hosts: [String]
    public var httpsCredentialRef: String?
    public var isDefault: Bool

    public init(
        id: String,
        displayName: String,
        gitUserName: String,
        gitUserEmail: String,
        sshKeyPath: String,
        hosts: [String],
        httpsCredentialRef: String?,
        isDefault: Bool
    ) throws {
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitAccountSwitcherError.emptyDisplayName
        }
        guard !gitUserName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitAccountSwitcherError.emptyGitUserName
        }
        guard !gitUserEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitAccountSwitcherError.emptyGitUserEmail
        }
        guard !sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitAccountSwitcherError.emptySSHKeyPath
        }
        guard hosts.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw GitAccountSwitcherError.emptyHost
        }

        self.id = id
        self.displayName = displayName
        self.gitUserName = gitUserName
        self.gitUserEmail = gitUserEmail
        self.sshKeyPath = sshKeyPath
        self.hosts = hosts
        self.httpsCredentialRef = httpsCredentialRef
        self.isDefault = isDefault
    }
}

public enum FolderRuleMatchMode: String, Codable, Equatable, Sendable {
    case folderTree
    case singleRepo
}

public struct FolderRule: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var path: String
    public var profileId: String
    public var matchMode: FolderRuleMatchMode
    public var enabled: Bool

    public init(
        id: String,
        path: String,
        profileId: String,
        matchMode: FolderRuleMatchMode,
        enabled: Bool
    ) {
        self.id = id
        self.path = path
        self.profileId = profileId
        self.matchMode = matchMode
        self.enabled = enabled
    }
}

public struct ProfileStoreData: Codable, Equatable, Sendable {
    public var profiles: [GitProfile]
    public var rules: [FolderRule]

    public init(profiles: [GitProfile] = [], rules: [FolderRule] = []) {
        self.profiles = profiles
        self.rules = rules
    }
}
