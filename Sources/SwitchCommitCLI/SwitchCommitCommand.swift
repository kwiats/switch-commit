import ArgumentParser

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct CLIOptions: ParsableArguments {
    @Flag(name: .long, help: "Emit machine-readable JSON output.")
    var json = false

    @Flag(name: .long, help: "Disable ANSI color output.")
    var noColor = false
}

struct SwitchCommitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "switch-commit",
        abstract: "Switch Commit CLI manages local Git identities safely.",
        subcommands: [
            ListCommand.self,
            StatusCommand.self,
            ShowCommand.self,
            UseCommand.self,
            AddCommand.self,
            EditCommand.self,
            DeleteCommand.self,
            Version.self
        ]
    )

    @OptionGroup
    var options: CLIOptions

    mutating func run() throws {
        if CommandLine.arguments.count == 1 {
            if isInteractiveSession {
                print("Interactive menu coming soon")
                return
            }

            CLIRuntime.terminate(
                code: .usage,
                message: "Run 'switch-commit --help' for usage.",
                json: options.json
            )
        }

        CLIRuntime.terminate(
            code: .usage,
            message: "Run 'switch-commit --help' for usage.",
            json: options.json
        )
    }

    private var isInteractiveSession: Bool {
        #if canImport(Darwin)
        return Darwin.isatty(Darwin.STDIN_FILENO) != 0 && Darwin.isatty(Darwin.STDOUT_FILENO) != 0
        #else
        return Glibc.isatty(Glibc.STDIN_FILENO) != 0 && Glibc.isatty(Glibc.STDOUT_FILENO) != 0
        #endif
    }

    struct Version: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "version",
            abstract: "Print the Switch Commit CLI version."
        )

        mutating func run() throws {
            print("switch-commit 0.3.0-dev")
        }
    }
}
