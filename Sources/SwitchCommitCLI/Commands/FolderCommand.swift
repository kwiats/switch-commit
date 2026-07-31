import ArgumentParser
import Foundation
import SwitchCommitCore

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct FolderCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "folder",
        abstract: "Manage folder-specific Git profile rules.",
        subcommands: [List.self, Add.self, Remove.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List folder-specific profile rules."
        )

        @OptionGroup
        var options: CLIOptions

        mutating func run() throws {
            do {
                let session = try CLIRuntime.session()
                let output = options.json
                    ? CLIOutput.jsonRules(rules: session.rules)
                    : CLIOutput.humanRules(
                        rules: session.rules,
                        profiles: session.profiles,
                        style: CLIRuntime.style(json: options.json, noColor: options.noColor)
                    )
                print(output)
            } catch {
                CLIRuntime.terminate(for: error, json: options.json)
            }
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Assign a profile to a folder."
        )

        @Argument(help: "Folder path to assign.")
        var path: String

        @Option(name: .long, help: "Profile ID or display name.")
        var profile: String

        @Option(name: .long, help: "Rule mode: folder-tree or single-repo.")
        var mode = "folder-tree"

        @Flag(name: .long, help: "Take over an existing rule without prompting.")
        var yes = false

        @OptionGroup
        var options: CLIOptions

        mutating func run() throws {
            guard let matchMode = folderRuleMatchMode else {
                CLIRuntime.terminate(
                    code: .usage,
                    message: "Mode must be 'folder-tree' or 'single-repo'.",
                    json: options.json
                )
            }

            do {
                let rule = try CLIRuntime.session().addFolderRule(
                    path: path,
                    profileReference: profile,
                    matchMode: matchMode,
                    moveIfOwned: yes
                )
                if options.json {
                    print(CLIOutput.jsonRules(rules: [rule]))
                } else {
                    print("Added folder rule: \(rule.path) → \(rule.profileId)")
                }
            } catch let error as FolderRuleMutationError {
                switch error {
                case .ownedByOtherProfile(let profileId):
                    CLIRuntime.terminate(
                        code: .usage,
                        message: "Folder '\(path)' is owned by profile '\(profileId)'. Pass --yes to take it over.",
                        json: options.json
                    )
                case .profileNotFound:
                    CLIRuntime.terminate(for: error, json: options.json)
                }
            } catch {
                CLIRuntime.terminate(for: error, json: options.json)
            }
        }

        private var folderRuleMatchMode: FolderRuleMatchMode? {
            switch mode {
            case "folder-tree": .folderTree
            case "single-repo": .singleRepo
            default: nil
            }
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "remove",
            abstract: "Remove a folder-specific profile rule."
        )

        @Argument(help: "Folder rule ID or path.")
        var reference: String

        @Flag(name: .long, help: "Remove without prompting for confirmation.")
        var yes = false

        @OptionGroup
        var options: CLIOptions

        mutating func run() throws {
            do {
                let session = try CLIRuntime.session()
                let rule = session.rules.first { $0.id == reference || $0.path == reference }
                guard let rule else {
                    CLIRuntime.terminate(
                        code: .usage,
                        message: "Folder rule '\(reference)' was not found.",
                        json: options.json
                    )
                }

                if !yes {
                    guard !options.json, isatty(STDIN_FILENO) != 0 else {
                        CLIRuntime.terminate(
                            code: .usage,
                            message: "Pass --yes to remove a folder rule without an interactive confirmation.",
                            json: options.json
                        )
                    }
                    print("Remove folder rule '\(rule.path)'? [y/N]: ", terminator: "")
                    fflush(stdout)
                    guard let response = readLine(), ["y", "yes"].contains(response.lowercased()) else {
                        print("Removal cancelled.")
                        return
                    }
                }

                try session.removeFolderRule(id: rule.id)
                print(options.json ? CLIOutput.jsonOK() : "Removed folder rule: \(rule.path)")
            } catch {
                CLIRuntime.terminate(for: error, json: options.json)
            }
        }
    }
}
