import ArgumentParser
import Foundation
import SwitchCommitCore

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show the active and contextual Git profile."
    )

    @Option(name: .long, help: "Path to inspect for a matching folder rule.")
    var path: String?

    @OptionGroup
    var options: CLIOptions

    mutating func run() throws {
        do {
            let session = try CLIRuntime.session()
            let snapshot = session.status(path: path ?? FileManager.default.currentDirectoryPath)
            let output = options.json
                ? CLIOutput.jsonStatus(snapshot: snapshot)
                : CLIOutput.humanStatus(
                    snapshot: snapshot,
                    style: CLIRuntime.style(json: options.json, noColor: options.noColor)
                )
            print(output)
        } catch {
            CLIRuntime.terminate(for: error, json: options.json)
        }
    }
}
