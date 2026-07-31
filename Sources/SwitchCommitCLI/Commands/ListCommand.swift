import ArgumentParser
import SwitchCommitCore

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List configured Git profiles.",
        aliases: ["ls"]
    )

    @OptionGroup
    var options: CLIOptions

    mutating func run() throws {
        do {
            let session = try CLIRuntime.session()
            let output: String
            if options.json {
                output = CLIOutput.jsonList(
                    profiles: session.profiles,
                    activeProfileId: session.activeProfile?.id
                )
            } else {
                output = CLIOutput.humanList(
                    profiles: session.profiles,
                    activeProfileId: session.activeProfile?.id,
                    style: CLIRuntime.style(json: options.json, noColor: options.noColor)
                )
            }
            print(output)
        } catch {
            CLIRuntime.terminate(for: error, json: options.json)
        }
    }
}
