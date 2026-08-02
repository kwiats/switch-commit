import Foundation

public struct MenuBarAppRelauncher: Sendable {
    public static let bundleIdentifier = "com.git-account-switcher.app"
    public static let applicationURL = URL(fileURLWithPath: "/Applications/Switch Commit.app")

    private let commandRunner: UncheckedSendableCommandRunner
    private let bundleIdentifier: String
    private let applicationURL: URL

    public init(
        commandRunner: any CommandRunning,
        bundleIdentifier: String = MenuBarAppRelauncher.bundleIdentifier,
        applicationURL: URL = MenuBarAppRelauncher.applicationURL
    ) {
        self.commandRunner = UncheckedSendableCommandRunner(commandRunner)
        self.bundleIdentifier = bundleIdentifier
        self.applicationURL = applicationURL
    }

    public init(
        bundleIdentifier: String = MenuBarAppRelauncher.bundleIdentifier,
        applicationURL: URL = MenuBarAppRelauncher.applicationURL
    ) {
        self.init(
            commandRunner: ProcessCommandRunner(),
            bundleIdentifier: bundleIdentifier,
            applicationURL: applicationURL
        )
    }

    /// Returns `true` when a running instance was quit and relaunch was attempted.
    public func relaunchIfRunning() throws -> Bool {
        guard try isRunning() else {
            return false
        }
        try quitRunningApplication()
        try openInstalledApplication()
        return true
    }

    private func isRunning() throws -> Bool {
        let script =
            "tell application \"System Events\" to (bundle identifier of processes) contains \"\(bundleIdentifier)\""
        let result = try commandRunner.value.run(
            "osascript",
            arguments: ["-e", script],
            workingDirectory: nil
        )
        let output = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return result.exitCode == 0 && (output == "true" || output == "1")
    }

    private func quitRunningApplication() throws {
        let script = "tell application id \"\(bundleIdentifier)\" to quit"
        let result = try commandRunner.value.run(
            "osascript",
            arguments: ["-e", script],
            workingDirectory: nil
        )
        guard result.exitCode == 0 else {
            throw MenuBarAppRelaunchError.quitFailed(result.standardError)
        }
    }

    private func openInstalledApplication() throws {
        let result = try commandRunner.value.run(
            "open",
            arguments: [applicationURL.path],
            workingDirectory: nil
        )
        guard result.exitCode == 0 else {
            throw MenuBarAppRelaunchError.openFailed(result.standardError)
        }
    }
}

public enum MenuBarAppRelaunchError: LocalizedError {
    case quitFailed(String)
    case openFailed(String)

    public var errorDescription: String? {
        switch self {
        case .quitFailed(let detail):
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Could not quit Switch Commit." : "Could not quit Switch Commit: \(trimmed)"
        case .openFailed(let detail):
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Could not open Switch Commit.app." : "Could not open Switch Commit.app: \(trimmed)"
        }
    }
}

private struct UncheckedSendableCommandRunner: @unchecked Sendable {
    let value: any CommandRunning

    init(_ value: any CommandRunning) {
        self.value = value
    }
}
