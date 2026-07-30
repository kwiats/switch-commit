import Foundation

public enum GitAccountProvider: String, Codable, Hashable, Sendable {
    case github
}

public enum DetectionConfidence: String, Codable, Hashable, Comparable, Sendable {
    case low
    case medium
    case high

    public static func < (lhs: DetectionConfidence, rhs: DetectionConfidence) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .low:
            return 0
        case .medium:
            return 1
        case .high:
            return 2
        }
    }
}

public enum DetectionSource: String, Codable, Hashable, Sendable {
    case githubCliHostsFile
    case githubCliInstalled
    case globalGitConfig
    case gitCredentialUsername
    case sshConfig
    case sshResolvedConfig
    case repositoryRemote
}

public struct GitHubRemoteAccount: Equatable, Sendable {
    public var owner: String
    public var repository: String

    public init(owner: String, repository: String) {
        self.owner = owner
        self.repository = repository
    }
}

public struct DetectionSignal: Equatable, Sendable {
    public var provider: GitAccountProvider
    public var username: String?
    public var gitUserName: String?
    public var gitUserEmail: String?
    public var sshKeyPath: String?
    public var accessMethods: [GitAccessMethod]
    public var hosts: [String]
    public var confidence: DetectionConfidence
    public var source: DetectionSource
    public var warnings: [String]

    public init(
        provider: GitAccountProvider,
        username: String? = nil,
        gitUserName: String? = nil,
        gitUserEmail: String? = nil,
        sshKeyPath: String? = nil,
        accessMethods: [GitAccessMethod] = [],
        hosts: [String] = ["github.com"],
        confidence: DetectionConfidence,
        source: DetectionSource,
        warnings: [String] = []
    ) {
        self.provider = provider
        self.username = username
        self.gitUserName = gitUserName
        self.gitUserEmail = gitUserEmail
        self.sshKeyPath = sshKeyPath
        self.accessMethods = accessMethods
        self.hosts = hosts
        self.confidence = confidence
        self.source = source
        self.warnings = warnings
    }
}

public struct DetectedGitAccount: Equatable, Identifiable, Sendable {
    public var id: String
    public var provider: GitAccountProvider
    public var username: String?
    public var gitUserName: String?
    public var gitUserEmail: String?
    public var sshKeyPath: String?
    public var accessMethods: [GitAccessMethod]
    public var hosts: [String]
    public var confidence: DetectionConfidence
    public var sources: [DetectionSource]
    public var warnings: [String]

    public init(
        id: String,
        provider: GitAccountProvider,
        username: String?,
        gitUserName: String?,
        gitUserEmail: String?,
        sshKeyPath: String?,
        accessMethods: [GitAccessMethod] = [],
        hosts: [String],
        confidence: DetectionConfidence,
        sources: [DetectionSource],
        warnings: [String]
    ) {
        self.id = id
        self.provider = provider
        self.username = username
        self.gitUserName = gitUserName
        self.gitUserEmail = gitUserEmail
        self.sshKeyPath = sshKeyPath
        self.accessMethods = accessMethods
        self.hosts = hosts
        self.confidence = confidence
        self.sources = sources
        self.warnings = warnings
    }
}
