import Foundation

public struct CommandResult: Equatable, Sendable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public protocol CommandRunning: AnyObject {
    func run(_ command: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult
}

public enum ProcessLaunchPath {
    /// Resolves `command` to an executable URL. Absolute/relative paths used as-is;
    /// bare names search PATH (and on Unix may use `/usr/bin/env` as last resort only if present).
    public static func executableURL(
        for command: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        if command.contains("/") || command.contains("\\") {
            return URL(fileURLWithPath: command)
        }
        let pathEnv = environment["PATH"] ?? ""
        #if os(Windows)
        let separator: Character = ";"
        let extensions = ["", ".exe", ".cmd", ".bat"]
        #else
        let separator: Character = ":"
        let extensions = [""]
        #endif
        for directory in pathEnv.split(separator: separator) {
            for ext in extensions {
                let candidate = URL(fileURLWithPath: String(directory))
                    .appendingPathComponent(command + ext)
                if fileManager.isExecutableFile(atPath: candidate.path)
                    || fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        #if !os(Windows)
        let env = URL(fileURLWithPath: "/usr/bin/env")
        if fileManager.fileExists(atPath: env.path) {
            return env // caller must pass [command]+args when using env
        }
        #endif
        return nil
    }
}

public final class ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ command: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
        let process = Process()
        if command.contains("/") || command.contains("\\") {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
        } else if let resolved = ProcessLaunchPath.executableURL(for: command) {
            if resolved.path == "/usr/bin/env" {
                process.executableURL = resolved
                process.arguments = [command] + arguments
            } else {
                process.executableURL = resolved
                process.arguments = arguments
            }
        } else {
            throw NSError(domain: "SwitchCommit", code: 127, userInfo: [
                NSLocalizedDescriptionKey: "Command not found in PATH: \(command)"
            ])
        }
        process.currentDirectoryURL = workingDirectory

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandResult(exitCode: process.terminationStatus, standardOutput: output, standardError: error)
    }
}

public struct DiagnosticsReport: Equatable, Sendable {
    public var values: [String: String]
    public var warnings: [String]

    public init(values: [String: String] = [:], warnings: [String] = []) {
        self.values = values
        self.warnings = warnings
    }
}

public enum HostConnectionTestStatus: Equatable, Sendable {
    case connected
    case failed
}

public struct HostConnectionTestResult: Equatable, Sendable {
    public var host: String
    public var status: HostConnectionTestStatus
    public var message: String

    public init(host: String, status: HostConnectionTestStatus, message: String) {
        self.host = host
        self.status = status
        self.message = message
    }
}

public struct DiagnosticsService {
    private let commandRunner: CommandRunning

    public init(commandRunner: CommandRunning = ProcessCommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func inspectInsteadOfEntries(at folderURL: URL) -> [InsteadOfEntry] {
        do {
            let result = try commandRunner.run(
                "git",
                arguments: ["config", "--show-origin", "--get-regexp", #"url\..*\.insteadof"#],
                workingDirectory: folderURL
            )
            guard result.exitCode == 0 else {
                return []
            }
            return InsteadOfConflictRemediator().parseGitConfigShowOriginRegexp(output: result.standardOutput)
        } catch {
            return []
        }
    }

    public func inspectGitIdentity(at folderURL: URL) -> DiagnosticsReport {
        var report = DiagnosticsReport()
        for key in ["user.name", "user.email", "core.sshCommand"] {
            let arguments = ["config", "--includes", "--show-origin", "--get", key]
            do {
                let result = try commandRunner.run("git", arguments: arguments, workingDirectory: folderURL)
                if result.exitCode == 0 {
                    report.values[key] = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    report.warnings.append("\(key): \(result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            } catch {
                report.warnings.append("\(key): \(error)")
            }
        }
        return report
    }

    public func manualSSHTestCommand(host: String) -> (command: String, arguments: [String]) {
        ("ssh", ["-T", host])
    }

    public func sshConnectionTestCommand(
        host: String,
        identityFile: String? = nil
    ) -> (command: String, arguments: [String]) {
        var arguments = ["-o", "BatchMode=yes"]
        if let identityFile {
            let trimmed = identityFile.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                arguments += ["-o", "IdentitiesOnly=yes", "-i", trimmed]
            }
        }
        arguments += ["-T", "git@\(host)"]
        return ("ssh", arguments)
    }

    public func testSSHConnection(
        host: String,
        identityFile: String? = nil
    ) -> HostConnectionTestResult {
        let testCommand = sshConnectionTestCommand(host: host, identityFile: identityFile)
        do {
            let result = try commandRunner.run(testCommand.command, arguments: testCommand.arguments, workingDirectory: nil)
            let message = connectionMessage(from: result)
            let isConnected = result.exitCode == 0 || isGitHubAuthenticated(host: host, message: message)
            return HostConnectionTestResult(
                host: host,
                status: isConnected ? .connected : .failed,
                message: message
            )
        } catch {
            return HostConnectionTestResult(host: host, status: .failed, message: String(describing: error))
        }
    }

    private func connectionMessage(from result: CommandResult) -> String {
        let combined = [result.standardOutput, result.standardError]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if combined.isEmpty {
            return "No output from SSH connection test."
        }
        return combined
    }

    private func isGitHubAuthenticated(host: String, message: String) -> Bool {
        host.caseInsensitiveCompare("github.com") == .orderedSame
            && message.localizedCaseInsensitiveContains("successfully authenticated")
    }
}
