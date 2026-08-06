import Foundation
#if canImport(Glibc)
@preconcurrency import Glibc
#endif

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
        #if canImport(Glibc)
        // `Foundation.Process` on Linux has been observed to hang forever inside
        // containers: the child exits and is reaped by corelibs-foundation's
        // internal monitor thread (confirmed via `wait4` in strace), but
        // `waitUntilExit()` never returns to the caller. Shelling out through raw
        // POSIX `posix_spawnp`/`waitpid` sidesteps that failure mode entirely.
        return try PosixCommandRunner.run(command, arguments: arguments, workingDirectory: workingDirectory)
        #else
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

        // Close the parent's copy of the pipe write ends after spawning so
        // `readDataToEndOfFile()` below reliably observes EOF once the child exits.
        try? stdout.fileHandleForWriting.close()
        try? stderr.fileHandleForWriting.close()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        return CommandResult(exitCode: process.terminationStatus, standardOutput: output, standardError: error)
        #endif
    }
}

#if canImport(Glibc)
/// Minimal POSIX process launcher used only on Linux in place of
/// `Foundation.Process` (see the comment in `ProcessCommandRunner.run` above).
private enum PosixCommandRunner {
    static func run(_ command: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
        var stdoutFDs: [Int32] = [-1, -1]
        var stderrFDs: [Int32] = [-1, -1]
        guard pipe(&stdoutFDs) == 0 else {
            throw NSError(domain: "SwitchCommit", code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "Failed to create a stdout pipe for \(command)."
            ])
        }
        guard pipe(&stderrFDs) == 0 else {
            close(stdoutFDs[0])
            close(stdoutFDs[1])
            throw NSError(domain: "SwitchCommit", code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "Failed to create a stderr pipe for \(command)."
            ])
        }

        var fileActions = posix_spawn_file_actions_t()
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_adddup2(&fileActions, stdoutFDs[1], 1)
        posix_spawn_file_actions_adddup2(&fileActions, stderrFDs[1], 2)
        posix_spawn_file_actions_addclose(&fileActions, stdoutFDs[0])
        posix_spawn_file_actions_addclose(&fileActions, stdoutFDs[1])
        posix_spawn_file_actions_addclose(&fileActions, stderrFDs[0])
        posix_spawn_file_actions_addclose(&fileActions, stderrFDs[1])

        var cArgs: [UnsafeMutablePointer<CChar>?] = ([command] + arguments).map { strdup($0) }
        cArgs.append(nil)
        defer { cArgs.forEach { free($0) } }

        // posix_spawn has no portable "set working directory" option, so the parent
        // temporarily chdir()s around the spawn call; the child inherits whatever
        // cwd is current at spawn time. This CLI only ever shells out sequentially
        // from a single thread, so the brief process-wide chdir is safe in practice.
        let previousDirectory = FileManager.default.currentDirectoryPath
        if let workingDirectory {
            _ = FileManager.default.changeCurrentDirectoryPath(workingDirectory.path)
        }

        var pid: pid_t = 0
        let spawnStatus = cArgs.withUnsafeMutableBufferPointer { argv -> Int32 in
            posix_spawnp(&pid, command, &fileActions, nil, argv.baseAddress!, environ)
        }

        if workingDirectory != nil {
            _ = FileManager.default.changeCurrentDirectoryPath(previousDirectory)
        }

        close(stdoutFDs[1])
        close(stderrFDs[1])

        guard spawnStatus == 0 else {
            close(stdoutFDs[0])
            close(stderrFDs[0])
            throw NSError(domain: "SwitchCommit", code: Int(spawnStatus), userInfo: [
                NSLocalizedDescriptionKey: "Failed to launch \(command): \(String(cString: strerror(spawnStatus)))"
            ])
        }

        let stdoutData = readAllAndClose(stdoutFDs[0])
        let stderrData = readAllAndClose(stderrFDs[0])

        var status: Int32 = 0
        waitpid(pid, &status, 0)
        let exitCode: Int32
        if status & 0x7f == 0 {
            exitCode = (status >> 8) & 0xff
        } else {
            exitCode = 128 + (status & 0x7f)
        }

        return CommandResult(
            exitCode: exitCode,
            standardOutput: String(data: stdoutData, encoding: .utf8) ?? "",
            standardError: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    private static func readAllAndClose(_ fd: Int32) -> Data {
        defer { close(fd) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytesRead = buffer.withUnsafeMutableBytes { pointer in
                read(fd, pointer.baseAddress, pointer.count)
            }
            guard bytesRead > 0 else { break }
            data.append(contentsOf: buffer[0..<bytesRead])
        }
        return data
    }
}
#endif

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
