import Foundation

public enum CLIVersion {
    public static let developmentFallback = "0.3.0-dev"

    public static func current(
        executableURL: URL = CLIVersion.defaultExecutableURL(),
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

        // Portable Linux/Windows installs have no app bundle; `switch-commit update` and
        // `Scripts/build-cli-release.sh` write a sibling `VERSION` file next to the binary.
        if let version = versionFromCompanionFile(nearExecutable: resolvedExecutable) {
            return version
        }

        return developmentFallback
    }

    /// Default `executableURL` used when a caller (i.e. `switch-commit` itself) doesn't
    /// override it. Bare `argument0` (e.g. a `switch-commit` invoked via `PATH`, as some
    /// shells pass the literal typed command name rather than the resolved path) isn't a
    /// valid filesystem path on its own, so this mirrors `CLIBinaryInstaller`'s preference
    /// for an OS-native running-executable lookup, falling back to a `PATH` search of
    /// `argument0` for bare names.
    public static func defaultExecutableURL() -> URL {
        if let native = CLIBinaryInstaller.nativeExecutablePath() {
            return URL(fileURLWithPath: native)
        }
        guard let argument0 = CommandLine.arguments.first, !argument0.isEmpty else {
            return URL(fileURLWithPath: "switch-commit")
        }
        if argument0.contains("/") || argument0.contains("\\") {
            return URL(fileURLWithPath: argument0)
        }
        if let resolved = ProcessLaunchPath.executableURL(for: argument0), resolved.path != "/usr/bin/env" {
            return resolved
        }
        return URL(fileURLWithPath: argument0)
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

    private static func versionFromCompanionFile(nearExecutable executableURL: URL) -> String? {
        let versionFile = executableURL.deletingLastPathComponent().appendingPathComponent("VERSION")
        guard let data = try? Data(contentsOf: versionFile),
              let text = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }
}
