import ArgumentParser
import Foundation
import SwitchCommitCore

struct AddCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a Git profile."
    )

    @Option(name: .long, help: "Profile display name.")
    var name: String

    @Option(name: .customLong("git-name"), help: "Git commit author name.")
    var gitName: String

    @Option(name: .customLong("git-email"), help: "Git commit author email.")
    var gitEmail: String

    @Option(name: .long, help: "Profile access method: ssh or https.")
    var access = "https"

    @Option(name: .customLong("ssh-key"), help: "SSH private key path. Required for SSH access.")
    var sshKey: String?

    @Option(name: .long, help: "Git host. Repeat for multiple hosts.")
    var host: [String] = []

    @Option(name: .customLong("https-credential-ref"), help: "Keychain credential reference identifier.")
    var httpsCredentialRef: String?

    @OptionGroup
    var options: CLIOptions

    mutating func run() throws {
        guard let accessMethod = GitAccessMethod(rawValue: access) else {
            CLIRuntime.terminate(
                code: .usage,
                message: "Access method must be 'ssh' or 'https'.",
                json: options.json
            )
        }
        guard accessMethod != .ssh || !(sshKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            CLIRuntime.terminate(
                code: .usage,
                message: "--ssh-key is required when --access ssh.",
                json: options.json
            )
        }

        do {
            let profile = try CLIRuntime.session().addProfile(
                displayName: name,
                gitUserName: gitName,
                gitUserEmail: gitEmail,
                accessMethod: accessMethod,
                sshKeyPath: sshKey ?? "",
                hosts: host.isEmpty ? ["github.com"] : host,
                httpsCredentialRef: httpsCredentialRef
            )
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
