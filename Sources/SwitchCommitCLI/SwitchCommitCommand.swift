import ArgumentParser
import SwitchCommitCore

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
        version: CLIVersion.current(),
        subcommands: [
            ListCommand.self,
            StatusCommand.self,
            ShowCommand.self,
            UseCommand.self,
            AddCommand.self,
            EditCommand.self,
            DeleteCommand.self,
            FolderCommand.self,
            DoctorCommand.self,
            UpdateCommand.self,
            Version.self
        ]
    )

    @OptionGroup
    var options: CLIOptions

    mutating func run() throws {
        if CommandLine.arguments.count == 1 {
            if isInteractiveSession {
                do {
                    var menu = InteractiveProfileMenu()
                    try menu.run(session: CLIRuntime.session())
                } catch {
                    CLIRuntime.terminate(for: error, json: options.json)
                }
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
        CLITerminal.isInteractive
    }

    struct Version: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "version",
            abstract: "Print the Switch Commit CLI version."
        )

        @OptionGroup
        var options: CLIOptions

        mutating func run() throws {
            let version = CLIVersion.current()
            print(options.json ? CLIOutput.jsonVersion(version) : "switch-commit \(version)")
        }
    }
}
