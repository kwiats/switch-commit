import ArgumentParser
import SwitchCommitCore

struct UseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "use",
        abstract: "Switch the global Git profile by ID or display name."
    )

    @Argument(help: "Profile ID or display name.")
    var reference: String

    @OptionGroup
    var options: CLIOptions

    mutating func run() throws {
        do {
            let session = try CLIRuntime.session()
            let profile = try session.show(reference: reference)
            try session.use(reference: profile.id)

            if options.json {
                print(CLIOutput.jsonOK())
            } else {
                print("Using profile: \(profile.id)")
            }
        } catch {
            CLIRuntime.terminate(for: error, json: options.json)
        }
    }
}
