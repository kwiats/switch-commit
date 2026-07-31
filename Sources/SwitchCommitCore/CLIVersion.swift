import Foundation

public enum CLIVersion {
    public static let developmentFallback = "0.3.0-dev"

    public static func current(
        executableURL: URL = URL(fileURLWithPath: CommandLine.arguments[0]),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if let releaseVersion = environment["SWITCH_COMMIT_VERSION"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !releaseVersion.isEmpty {
            return releaseVersion
        }

        let infoPlist = executableURL
            .standardizedFileURL
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
            return developmentFallback
        }

        return version
    }
}
