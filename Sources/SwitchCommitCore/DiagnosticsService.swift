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

public final class ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ command: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
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

    public func sshConnectionTestCommand(host: String) -> (command: String, arguments: [String]) {
        ("ssh", ["-o", "BatchMode=yes", "-T", "git@\(host)"])
    }

    public func testSSHConnection(host: String) -> HostConnectionTestResult {
        let testCommand = sshConnectionTestCommand(host: host)
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
