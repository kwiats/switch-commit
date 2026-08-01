import Foundation

public enum CLIVersion {
    public static let developmentFallback = "0.3.0-dev"

    public static func current(
        executableURL: URL = URL(fileURLWithPath: CommandLine.arguments[0]),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String {
        if let releaseVersion = environment["SWITCH_COMMIT_VERSION"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !releaseVersion.isEmpty {
            return releaseVersion
        }

        let resolvedExecutable = resolveExecutableURL(executableURL, fileManager: fileManager)
        if let version = versionFromInfoPlist(nearExecutable: resolvedExecutable) {
            return version
        }

        // /usr/local/bin stub or launch script → read packaged app Info.plist.
        if resolvedExecutable.deletingLastPathComponent().path == "/usr/local/bin" {
            let applicationsCLI = URL(
                fileURLWithPath: "/Applications/Switch Commit.app/Contents/MacOS/switch-commit"
            )
            if let version = versionFromInfoPlist(nearExecutable: applicationsCLI) {
                return version
            }
        }

        return developmentFallback
    }

    private static func resolveExecutableURL(_ executableURL: URL, fileManager: FileManager) -> URL {
        let url = executableURL.standardizedFileURL
        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) {
            let resolved = URL(fileURLWithPath: destination, relativeTo: url.deletingLastPathComponent())
                .standardizedFileURL
            return resolved
        }
        return url
    }

    private static func versionFromInfoPlist(nearExecutable executableURL: URL) -> String? {
        let infoPlist = executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Info.plist")

        guard let data = try? Data(contentsOf: infoPlist),
              let propertyList = try? PropertyListSerialization.propertyList(
                  from: data,
                  format: nil
              ) as? [String: Any],
              let version = propertyList["CFBundleShortVersionString"] as? String,
              !version.isEmpty else {
            return nil
        }
        return version
    }
}
