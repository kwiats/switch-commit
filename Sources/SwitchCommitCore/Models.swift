import Foundation

public enum FolderRuleError: Error, Equatable, Sendable {
    case unknownProfile
    case pathOwnedByOtherProfile(profileId: String)
    case ruleNotFound
}

public enum SwitchCommitError: Error, Equatable {
    case emptyDisplayName
    case emptyGitUserName
    case emptyGitUserEmail
    case emptySSHKeyPath
    case emptyHost
    case emptyFolderRulePath
    case writeOutsideManagedRoots
    case unsafeConfigValue
    case unsafeIdentifier
    case profileStoreUnavailable
}

public enum GitAccessMethod: String, Codable, Equatable, Sendable {
    case ssh
    case https
}

public struct GitProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var displayName: String
    public var gitUserName: String
    public var gitUserEmail: String
    public var accessMethod: GitAccessMethod
    public var sshKeyPath: String
    public var hosts: [String]
    public var httpsCredentialRef: String?
    public var isDefault: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case gitUserName
        case gitUserEmail
        case accessMethod
        case sshKeyPath
        case hosts
        case httpsCredentialRef
        case isDefault
    }

    public init(
        id: String,
        displayName: String,
        gitUserName: String,
        gitUserEmail: String,
        accessMethod: GitAccessMethod = .ssh,
        sshKeyPath: String,
        hosts: [String],
        httpsCredentialRef: String?,
        isDefault: Bool
    ) throws {
        try SecurityValidation.requireSafeIdentifier(id)
        if let httpsCredentialRef {
            try SecurityValidation.requireSafeIdentifier(httpsCredentialRef)
        }
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SwitchCommitError.emptyDisplayName
        }
        guard !gitUserName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SwitchCommitError.emptyGitUserName
        }
        guard !gitUserEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SwitchCommitError.emptyGitUserEmail
        }
        if accessMethod == .ssh {
            guard !sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SwitchCommitError.emptySSHKeyPath
            }
        }
        guard hosts.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw SwitchCommitError.emptyHost
        }
        try SecurityValidation.requireSafeConfigValues([
            displayName,
            gitUserName,
            gitUserEmail,
            sshKeyPath
        ] + hosts)

        self.id = id
        self.displayName = displayName
        self.gitUserName = gitUserName
        self.gitUserEmail = gitUserEmail
        self.accessMethod = accessMethod
        self.sshKeyPath = sshKeyPath
        self.hosts = hosts
        self.httpsCredentialRef = httpsCredentialRef
        self.isDefault = isDefault
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: try container.decode(String.self, forKey: .id),
            displayName: try container.decode(String.self, forKey: .displayName),
            gitUserName: try container.decode(String.self, forKey: .gitUserName),
            gitUserEmail: try container.decode(String.self, forKey: .gitUserEmail),
            accessMethod: try container.decodeIfPresent(GitAccessMethod.self, forKey: .accessMethod) ?? .ssh,
            sshKeyPath: try container.decode(String.self, forKey: .sshKeyPath),
            hosts: try container.decode([String].self, forKey: .hosts),
            httpsCredentialRef: try container.decodeIfPresent(String.self, forKey: .httpsCredentialRef),
            isDefault: try container.decode(Bool.self, forKey: .isDefault)
        )
    }
}

public enum FolderRuleMatchMode: String, Codable, Equatable, Sendable {
    case folderTree
    case singleRepo
}

public enum FolderRuleMutationError: Error, Equatable, Sendable {
    case ownedByOtherProfile(profileId: String)
    case profileNotFound(profileId: String)
}

public struct FolderRule: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var path: String
    public var profileId: String
    public var matchMode: FolderRuleMatchMode
    public var enabled: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case path
        case profileId
        case matchMode
        case enabled
    }

    public init(
        id: String,
        path: String,
        profileId: String,
        matchMode: FolderRuleMatchMode,
        enabled: Bool
    ) throws {
        try SecurityValidation.requireSafeIdentifier(id)
        try SecurityValidation.requireSafeIdentifier(profileId)
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SwitchCommitError.emptyFolderRulePath
        }
        try SecurityValidation.requireSafeConfigValues([path])

        self.id = id
        self.path = path
        self.profileId = profileId
        self.matchMode = matchMode
        self.enabled = enabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: try container.decode(String.self, forKey: .id),
            path: try container.decode(String.self, forKey: .path),
            profileId: try container.decode(String.self, forKey: .profileId),
            matchMode: try container.decode(FolderRuleMatchMode.self, forKey: .matchMode),
            enabled: try container.decode(Bool.self, forKey: .enabled)
        )
    }
}

public enum PersistedHostConnectionTestStatus: String, Codable, Equatable, Sendable {
    case connected
    case failed
}

public struct PersistedHostConnectionTestResult: Codable, Equatable, Sendable {
    public var host: String
    public var status: PersistedHostConnectionTestStatus
    public var message: String

    public init(host: String, status: PersistedHostConnectionTestStatus, message: String) {
        self.host = host
        self.status = status
        self.message = message
    }
}

public struct PersistedProfileConnectionState: Codable, Equatable, Sendable {
    public var profileId: String
    public var testedAt: String
    public var results: [PersistedHostConnectionTestResult]

    public init(profileId: String, testedAt: String, results: [PersistedHostConnectionTestResult]) {
        self.profileId = profileId
        self.testedAt = testedAt
        self.results = results
    }
}

public struct ProfileStoreData: Codable, Equatable, Sendable {
    public var profiles: [GitProfile]
    public var rules: [FolderRule]
    public var profileConnectionStates: [String: PersistedProfileConnectionState]

    private enum CodingKeys: String, CodingKey {
        case profiles
        case rules
        case profileConnectionStates
    }

    public init(
        profiles: [GitProfile] = [],
        rules: [FolderRule] = [],
        profileConnectionStates: [String: PersistedProfileConnectionState] = [:]
    ) {
        self.profiles = profiles
        self.rules = rules
        self.profileConnectionStates = profileConnectionStates
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            profiles: try container.decode([GitProfile].self, forKey: .profiles),
            rules: try container.decode([FolderRule].self, forKey: .rules),
            profileConnectionStates: try container.decodeIfPresent(
                [String: PersistedProfileConnectionState].self,
                forKey: .profileConnectionStates
            ) ?? [:]
        )
    }
}

enum SecurityValidation {
    static func requireSafeIdentifier(_ value: String) throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard !value.isEmpty,
              value.rangeOfCharacter(from: allowed.inverted) == nil,
              value != ".",
              value != "..",
              !value.hasPrefix("."),
              !value.contains("..") else {
            throw SwitchCommitError.unsafeIdentifier
        }
    }

    static func requireSafeConfigValues(_ values: [String]) throws {
        for value in values {
            if value.unicodeScalars.contains(where: { $0.value == 0 || $0.value == 10 || $0.value == 13 }) {
                throw SwitchCommitError.unsafeConfigValue
            }
        }
    }
}
