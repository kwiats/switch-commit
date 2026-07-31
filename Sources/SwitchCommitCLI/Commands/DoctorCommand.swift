import ArgumentParser
import Foundation
import SwitchCommitCore

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Inspect the local Git identity at a path."
    )

    @Option(name: .long, help: "Path to inspect. Defaults to the current directory.")
    var path: String?

    @OptionGroup
    var options: CLIOptions

    mutating func run() throws {
        do {
            let report = try CLIRuntime.session().doctor(
                path: path ?? FileManager.default.currentDirectoryPath
            )
            let output = options.json
                ? CLIOutput.jsonDoctor(report: report)
                : CLIOutput.humanDoctor(
                    report: report,
                    style: CLIRuntime.style(json: options.json, noColor: options.noColor)
                )
            print(output)
        } catch {
            CLIRuntime.terminate(for: error, json: options.json)
        }
    }
}
