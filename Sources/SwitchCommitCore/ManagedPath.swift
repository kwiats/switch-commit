import Foundation

public enum ManagedPath: Sendable {
    /// True when `url` is exactly `root` or a descendant (component-wise), after standardization.
    public static func isEqualOrDescendant(_ url: URL, of root: URL) -> Bool {
        let left = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let right = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard left.count >= right.count else { return false }
        return zip(left, right).allSatisfy(==)
    }

    public static func isEqualOrDescendantPath(_ path: String, of rootPath: String) -> Bool {
        isEqualOrDescendant(
            URL(fileURLWithPath: path),
            of: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
    }
}
