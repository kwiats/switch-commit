import Foundation
import SwitchCommitCore

public enum FrontmostPathSource: String, Equatable, Sendable {
    case finder
    case terminal
    case iterm
    case cursor
    case vsCode
}

public struct FolderAssignmentRow: Equatable, Identifiable, Sendable {
    public var id: String
    public var path: String
    public var matchMode: FolderRuleMatchMode

    public init(id: String, path: String, matchMode: FolderRuleMatchMode) {
        self.id = id
        self.path = path
        self.matchMode = matchMode
    }
}

public struct FolderContextPresentation: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case folder(path: String, profileDisplayName: String)
        case global(profileDisplayName: String)
        case unavailable(reason: String)
    }

    public var kind: Kind
    public var menuTitle: String
    public var menuHeader: String

    public static func from(
        resolution: FolderRuleResolution,
        path: String?,
        unavailableReason: String?
    ) -> FolderContextPresentation {
        if let unavailableReason {
            return FolderContextPresentation(
                kind: .unavailable(reason: unavailableReason),
                menuTitle: resolution.profile?.displayName ?? "Switch Commit",
                menuHeader: "Context: unavailable (\(unavailableReason))"
            )
        }

        switch resolution.kind {
        case .folderRule:
            let name = resolution.profile?.displayName ?? "Unknown"
            let displayPath = path ?? resolution.rule?.path ?? ""
            return FolderContextPresentation(
                kind: .folder(path: displayPath, profileDisplayName: name),
                menuTitle: "\(name) · \(shortPath(displayPath))",
                menuHeader: "Context: \(displayPath) → \(name)"
            )
        case .global:
            let name = resolution.profile?.displayName ?? "No profile"
            return FolderContextPresentation(
                kind: .global(profileDisplayName: name),
                menuTitle: name,
                menuHeader: "Context: Global → \(name)"
            )
        }
    }

    private static func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

public protocol FrontmostPathProviding: AnyObject {
    func currentFrontmostPath() -> (path: String, source: FrontmostPathSource)?
}
