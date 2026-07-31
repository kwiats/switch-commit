import Foundation
import SwitchCommitAppLogic

struct CLIInstallManager: CLIInstalling {
    private let linkURL: URL
    private let bundledCLIURL: URL

    init(
        linkURL: URL = URL(fileURLWithPath: "/usr/local/bin/switch-commit"),
        bundledCLIURL: URL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/switch-commit")
    ) {
        self.linkURL = linkURL
        self.bundledCLIURL = bundledCLIURL
    }

    var statusMessage: String {
        guard FileManager.default.fileExists(atPath: bundledCLIURL.path) else {
            return "CLI is broken: the bundled executable is unavailable."
        }

        do {
            let destination = try FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path)
            let destinationURL = URL(fileURLWithPath: destination, relativeTo: linkURL.deletingLastPathComponent())
                .standardizedFileURL
            guard destinationURL == bundledCLIURL.standardizedFileURL else {
                return "CLI is broken: /usr/local/bin/switch-commit points to a different executable."
            }
            return "CLI is installed at /usr/local/bin/switch-commit."
        } catch {
            guard FileManager.default.fileExists(atPath: linkURL.path) else {
                return "CLI is missing from /usr/local/bin/switch-commit."
            }
            return "CLI is broken: /usr/local/bin/switch-commit is not a symbolic link."
        }
    }

    func installOrRepair() throws {
        guard FileManager.default.fileExists(atPath: bundledCLIURL.path) else {
            throw CLIInstallError.bundledExecutableMissing
        }

        do {
            try installLink()
        } catch {
            guard Self.isPermissionError(error) else {
                throw error
            }
            try installLinkWithAdministratorPrivileges()
        }
    }

    private func installLink() throws {
        do {
            _ = try FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path)
            try FileManager.default.removeItem(at: linkURL)
        } catch {
            if FileManager.default.fileExists(atPath: linkURL.path) {
                throw CLIInstallError.existingNonSymlink(linkURL.path)
            }
        }
        try FileManager.default.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: bundledCLIURL)
    }

    private func installLinkWithAdministratorPrivileges() throws {
        let command = [
            "/bin/mkdir -p \(shellQuoted(linkURL.deletingLastPathComponent().path))",
            "/bin/rm -f \(shellQuoted(linkURL.path))",
            "/bin/ln -s \(shellQuoted(bundledCLIURL.path)) \(shellQuoted(linkURL.path))"
        ].joined(separator: " && ")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \(appleScriptQuoted(command)) with administrator privileges"]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CLIInstallError.administratorInstallFailed
        }
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptQuoted(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func isPermissionError(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSPOSIXErrorDomain && (error.code == EACCES || error.code == EPERM)
            || error.domain == NSCocoaErrorDomain && error.code == CocoaError.fileWriteNoPermission.rawValue
    }
}

private enum CLIInstallError: LocalizedError {
    case bundledExecutableMissing
    case existingNonSymlink(String)
    case administratorInstallFailed

    var errorDescription: String? {
        switch self {
        case .bundledExecutableMissing:
            return "The bundled switch-commit executable is unavailable."
        case .existingNonSymlink(let path):
            return "\(path) exists and is not a symbolic link."
        case .administratorInstallFailed:
            return "Administrator authorization was cancelled or the link could not be created."
        }
    }
}
