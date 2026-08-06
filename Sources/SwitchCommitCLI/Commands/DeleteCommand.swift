import ArgumentParser
import SwitchCommitCore

#if os(Windows)
import ucrt
#elseif canImport(Darwin)
import Darwin
#else
@preconcurrency import Glibc
#endif

struct DeleteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a Git profile by ID or display name."
    )

    @Argument(help: "Profile ID or display name.")
    var reference: String

    @Flag(name: .long, help: "Delete without prompting for confirmation.")
    var yes = false

    @OptionGroup
    var options: CLIOptions

    mutating func run() throws {
        do {
            let session = try CLIRuntime.session()
            let profile = try session.show(reference: reference)

            if !yes {
                guard !options.json, isInteractiveSession else {
                    CLIRuntime.terminate(
                        code: .usage,
                        message: "Pass --yes to delete a profile without an interactive confirmation.",
                        json: options.json
                    )
                }

                print("Delete profile '\(profile.id)'? [y/N]: ", terminator: "")
                fflush(stdout)
                guard let response = readLine(), ["y", "yes"].contains(response.lowercased()) else {
                    print("Deletion cancelled.")
                    return
                }
            }

            try session.deleteProfile(reference: profile.id)
            if options.json {
                print(CLIOutput.jsonOK())
            } else {
                print("Deleted profile: \(profile.id)")
            }
        } catch {
            CLIRuntime.terminate(for: error, json: options.json)
        }
    }

    private var isInteractiveSession: Bool {
        CLITerminal.isStandardInputTTY
    }
}
