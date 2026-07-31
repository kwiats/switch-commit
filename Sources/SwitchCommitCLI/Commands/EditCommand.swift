import ArgumentParser
import SwitchCommitCore

struct EditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Edit a Git profile by ID or display name."
    )

    @Argument(help: "Profile ID or display name.")
    var reference: String

    @Option(name: .long, help: "Profile display name.")
    var name: String?

    @Option(name: .customLong("git-name"), help: "Git commit author name.")
    var gitName: String?

    @Option(name: .customLong("git-email"), help: "Git commit author email.")
    var gitEmail: String?

    @Option(name: .long, help: "Profile access method: ssh or https.")
    var access: String?

    @Option(name: .customLong("ssh-key"), help: "SSH private key path.")
    var sshKey: String?

    @Option(name: .long, help: "Git host. Repeat to replace the host list.")
    var host: [String] = []

    @Option(name: .customLong("https-credential-ref"), help: "Keychain credential reference identifier.")
    var httpsCredentialRef: String?

    @OptionGroup
    var options: CLIOptions

    mutating func run() throws {
        let accessMethod: GitAccessMethod?
        if let access {
            guard let parsedAccessMethod = GitAccessMethod(rawValue: access) else {
                CLIRuntime.terminate(
                    code: .usage,
                    message: "Access method must be 'ssh' or 'https'.",
                    json: options.json
                )
            }
            accessMethod = parsedAccessMethod
        } else {
            accessMethod = nil
        }

        do {
            let profile = try CLIRuntime.session().editProfile(
                reference: reference,
                displayName: name,
                gitUserName: gitName,
                gitUserEmail: gitEmail,
                accessMethod: accessMethod,
                sshKeyPath: sshKey,
                hosts: host.isEmpty ? nil : host,
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
