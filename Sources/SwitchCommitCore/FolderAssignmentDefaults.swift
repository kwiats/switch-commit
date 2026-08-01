import Foundation

public struct FolderAssignmentDefaults: Equatable, Sendable {
    public var path: String
    public var profileReference: String
    public var matchMode: FolderRuleMatchMode

    public init(path: String, profileReference: String, matchMode: FolderRuleMatchMode) {
        self.path = path
        self.profileReference = profileReference
        self.matchMode = matchMode
    }

    public enum ResolutionError: Error, Equatable, Sendable {
        case missingActiveProfile
        case invalidMode(String)
    }

    /// Resolves CLI defaults for `folder add` when path/profile/mode are omitted.
    /// Uses the active global profile and infers `single-repo` when `.git` exists at the path.
    public static func resolve(
        path: String?,
        profileReference: String?,
        mode: String?,
        activeProfile: GitProfile?,
        currentDirectory: String,
        homeDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> FolderAssignmentDefaults {
        let resolvedPath = FolderRuleResolver.normalize(
            path?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? currentDirectory,
            homeDirectory: homeDirectory
        )

        let resolvedProfile: String
        if let profileReference, let trimmed = profileReference.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            resolvedProfile = trimmed
        } else if let activeProfile {
            resolvedProfile = activeProfile.id
        } else {
            throw ResolutionError.missingActiveProfile
        }

        let resolvedMode: FolderRuleMatchMode
        if let mode, let trimmed = mode.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            switch trimmed {
            case "folder-tree":
                resolvedMode = .folderTree
            case "single-repo":
                resolvedMode = .singleRepo
            default:
                throw ResolutionError.invalidMode(trimmed)
            }
        } else {
            resolvedMode = inferredMatchMode(at: resolvedPath, fileManager: fileManager)
        }

        return FolderAssignmentDefaults(
            path: resolvedPath,
            profileReference: resolvedProfile,
            matchMode: resolvedMode
        )
    }

    public static func inferredMatchMode(
        at path: String,
        fileManager: FileManager = .default
    ) -> FolderRuleMatchMode {
        let gitPath = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent(".git")
            .path
        return fileManager.fileExists(atPath: gitPath) ? .singleRepo : .folderTree
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
