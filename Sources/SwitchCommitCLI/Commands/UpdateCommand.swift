import ArgumentParser
import Foundation
import SwitchCommitCore

struct UpdateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Check the public release channel and install the latest Switch Commit app + CLI. "
            + "Installs the app DMG on macOS, or replaces the running CLI binary on Linux/Windows."
    )

    @OptionGroup
    var options: CLIOptions

    mutating func run() throws {
        let current = CLIVersion.current()
        let service = ReleaseChannelUpdateService()

        let snapshot: ReleaseChannelSnapshot
        do {
            snapshot = try service.refresh()
        } catch {
            CLIRuntime.terminate(
                code: .failure,
                message: "Could not check for updates: \(error.localizedDescription)",
                json: options.json
            )
        }

        guard VersionComparator.isNewer(snapshot.latestVersion, than: current) else {
            let message = "Switch Commit \(current) is up to date."
            if options.json {
                print(CLIOutput.jsonMessage(message))
            } else {
                print(message)
            }
            return
        }

        if options.json {
            // Machine-readable clients get the target version; installation stays interactive/human.
            print(CLIOutput.jsonMessage("Update available: \(snapshot.latestVersion)"))
        } else {
            print("Update available: \(current) → \(snapshot.latestVersion)")
        }

        #if os(macOS)
        do {
            if !options.json {
                print("Downloading \(snapshot.enclosureURL.absoluteString) …")
            }
            let installer = AppReleaseInstaller()
            try installer.install(from: snapshot.enclosureURL, expectedVersion: snapshot.latestVersion)
            try installer.repairCLISymlink()
            let installed = CLIVersion.current()
            var done = "Installed Switch Commit \(installed). CLI repaired at /usr/local/bin/switch-commit."
            do {
                if try MenuBarAppRelauncher().relaunchIfRunning() {
                    done += " Menu bar app restarted."
                }
            } catch {
                let warning =
                    " Could not restart Switch Commit automatically; quit and reopen the app to load the update. (\(error.localizedDescription))"
                done += warning
                if !options.json {
                    fputs("warning:\(warning)\n", stderr)
                }
            }
            if options.json {
                print(CLIOutput.jsonMessage(done))
            } else {
                print(done)
            }
        } catch {
            CLIRuntime.terminate(for: error, json: options.json)
        }
        #else
        do {
            let installer = CLIBinaryInstaller()
            let os = CLIReleaseAsset.currentOS()
            let arch = CLIReleaseAsset.currentArch()
            let assetURL = CLIReleaseAsset.downloadURL(
                version: snapshot.latestVersion,
                os: os,
                arch: arch
            )
            if !options.json {
                print("Downloading \(assetURL.absoluteString) …")
            }

            let temporaryRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("switch-commit-cli-update-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporaryRoot) }

            let downloadedBinary = temporaryRoot.appendingPathComponent(CLIReleaseAsset.fileName(os: os, arch: arch))
            do {
                try installer.download(assetURL, to: downloadedBinary)
            } catch {
                throw CLIBinaryInstallerError.assetMissing
            }

            // A missing .sha256 file is not fatal; a present-but-mismatched one is.
            if let expectedHex = installer.readSHA256SumFile(at: CLIReleaseAsset.sha256URL(for: assetURL)) {
                try installer.verifySHA256(fileURL: downloadedBinary, expectedHex: expectedHex)
            }

            let runningExecutable = try installer.resolveRunningExecutable()
            try installer.replaceExecutable(
                at: runningExecutable,
                with: downloadedBinary,
                version: snapshot.latestVersion
            )

            let done = "Installed switch-commit \(snapshot.latestVersion) at \(runningExecutable.path)."
            if options.json {
                print(CLIOutput.jsonMessage(done))
            } else {
                print(done)
            }
        } catch {
            CLIRuntime.terminate(for: error, json: options.json)
        }
        #endif
    }
}

#if os(macOS)
struct AppReleaseInstaller {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func install(from enclosureURL: URL, expectedVersion: String) throws {
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("switch-commit-update-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let dmgURL = temporaryRoot.appendingPathComponent("SwitchCommit.dmg")
        try download(enclosureURL, to: dmgURL)
        try verifySHA256IfAvailable(enclosureURL: enclosureURL, dmgURL: dmgURL)

        let mountPoint = temporaryRoot.appendingPathComponent("mount", isDirectory: true)
        try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", arguments: [
            "attach", dmgURL.path,
            "-nobrowse",
            "-readonly",
            "-mountpoint", mountPoint.path
        ])
        defer {
            _ = try? run("/usr/bin/hdiutil", arguments: ["detach", mountPoint.path, "-force"])
        }

        guard let appURL = findApp(in: mountPoint) else {
            throw AppReleaseInstallError.appMissingInDMG
        }

        let destination = URL(fileURLWithPath: "/Applications/Switch Commit.app")
        try installApp(from: appURL, to: destination)
        _ = expectedVersion
    }

    func repairCLISymlink() throws {
        let link = URL(fileURLWithPath: "/usr/local/bin/switch-commit")
        let target = URL(fileURLWithPath: "/Applications/Switch Commit.app/Contents/MacOS/switch-commit")
        guard fileManager.fileExists(atPath: target.path) else {
            throw AppReleaseInstallError.bundledCLIMissing
        }

        do {
            if fileManager.fileExists(atPath: link.path) {
                try fileManager.removeItem(at: link)
            }
            try fileManager.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.createSymbolicLink(at: link, withDestinationURL: target)
        } catch {
            try repairCLIWithAdministratorPrivileges(link: link, target: target)
        }
    }

    private func installApp(from source: URL, to destination: URL) throws {
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            try installAppWithAdministratorPrivileges(from: source, to: destination)
        }
    }

    private func download(_ url: URL, to destination: URL) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var resultError: Error?
        let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            defer { semaphore.signal() }
            if let error {
                resultError = error
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                resultError = URLError(.badServerResponse)
                return
            }
            guard let tempURL else {
                resultError = URLError(.badURL)
                return
            }
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)
            } catch {
                resultError = error
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 300)
        if let resultError {
            throw resultError
        }
        guard fileManager.fileExists(atPath: destination.path) else {
            throw AppReleaseInstallError.downloadFailed
        }
    }

    private func verifySHA256IfAvailable(enclosureURL: URL, dmgURL: URL) throws {
        let shaURL = URL(string: enclosureURL.absoluteString + ".sha256")!
        let semaphore = DispatchSemaphore(value: 0)
        var remoteText: String?
        let task = URLSession.shared.dataTask(with: shaURL) { data, response, _ in
            defer { semaphore.signal() }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let data,
                  let text = String(data: data, encoding: .utf8) else {
                return
            }
            remoteText = text
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 15)
        guard let remoteText else {
            return
        }
        let expected = remoteText
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init)?
            .lowercased()
        guard let expected, expected.count == 64 else {
            return
        }
        let result = try run("/usr/bin/shasum", arguments: ["-a", "256", dmgURL.path])
        let actual = result.standardOutput
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init)?
            .lowercased()
        guard actual == expected else {
            throw AppReleaseInstallError.checksumMismatch
        }
    }

    private func findApp(in directory: URL) -> URL? {
        let contents = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.first { $0.pathExtension == "app" }
    }

    @discardableResult
    private func run(_ launchPath: String, arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let result = CommandResult(
            exitCode: process.terminationStatus,
            standardOutput: output,
            standardError: error
        )
        guard result.exitCode == 0 else {
            throw AppReleaseInstallError.commandFailed(launchPath, result.standardError)
        }
        return result
    }

    private func installAppWithAdministratorPrivileges(from source: URL, to destination: URL) throws {
        let command = [
            "/bin/rm -rf \(shellQuoted(destination.path))",
            "/bin/cp -R \(shellQuoted(source.path)) \(shellQuoted(destination.path))"
        ].joined(separator: " && ")
        try runAdminShell(command)
    }

    private func repairCLIWithAdministratorPrivileges(link: URL, target: URL) throws {
        let command = [
            "/bin/mkdir -p \(shellQuoted(link.deletingLastPathComponent().path))",
            "/bin/rm -f \(shellQuoted(link.path))",
            "/bin/ln -s \(shellQuoted(target.path)) \(shellQuoted(link.path))"
        ].joined(separator: " && ")
        try runAdminShell(command)
    }

    private func runAdminShell(_ command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \(appleScriptQuoted(command)) with administrator privileges"
        ]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AppReleaseInstallError.administratorInstallFailed
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
}

private enum AppReleaseInstallError: LocalizedError {
    case appMissingInDMG
    case bundledCLIMissing
    case downloadFailed
    case checksumMismatch
    case administratorInstallFailed
    case commandFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .appMissingInDMG:
            return "The downloaded DMG did not contain Switch Commit.app."
        case .bundledCLIMissing:
            return "Installed app is missing Contents/MacOS/switch-commit."
        case .downloadFailed:
            return "Failed to download the Switch Commit DMG."
        case .checksumMismatch:
            return "Downloaded DMG failed SHA-256 verification."
        case .administratorInstallFailed:
            return "Administrator authorization was cancelled or installation failed."
        case .commandFailed(let command, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "Command failed: \(command)" : "\(command): \(detail)"
        }
    }
}
#endif
