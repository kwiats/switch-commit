import ArgumentParser
import SwitchCommitCore

struct ShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show a Git profile by ID or display name."
    )

    @Argument(help: "Profile ID or display name.")
    var reference: String

    @OptionGroup
    var options: CLIOptions

    mutating func run() throws {
        do {
            let profile = try CLIRuntime.session().show(reference: reference)
            let output = options.json
                ? CLIOutput.jsonShow(profile: profile)
                : CLIOutput.humanShow(
                    profile: profile,
                    style: CLIRuntime.style(json: options.json, noColor: options.noColor)
                )
            print(output)
        } catch {
            CLIRuntime.terminate(for: error, json: options.json)
        }
    }
}
