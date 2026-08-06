import ArgumentParser
@preconcurrency import Foundation
import SwitchCommitCore

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
            abstract: "Assign a profile to a folder. Defaults to the current directory, active profile, and single-repo when .git exists."
        )

        @Argument(help: "Folder path to assign. Defaults to the current directory.")
        var path: String?

        @Option(name: .long, help: "Profile ID or display name. Defaults to the active global profile.")
        var profile: String?

        @Option(name: .long, help: "Rule mode: folder-tree or single-repo. Defaults from .git presence.")
        var mode: String?

        @Flag(name: .long, help: "Take over an existing rule without prompting.")
        var yes = false

        @OptionGroup
        var options: CLIOptions

        mutating func run() throws {
            do {
                let session = try CLIRuntime.session()
                let defaults: FolderAssignmentDefaults
                do {
                    defaults = try FolderAssignmentDefaults.resolve(
                        path: path,
                        profileReference: profile,
                        mode: mode,
                        activeProfile: session.activeProfile,
                        currentDirectory: FileManager.default.currentDirectoryPath,
                        homeDirectory: FileManager.default.homeDirectoryForCurrentUser
                    )
                } catch let error as FolderAssignmentDefaults.ResolutionError {
                    switch error {
                    case .missingActiveProfile:
                        CLIRuntime.terminate(
                            code: .usage,
                            message: "No active profile. Pass --profile or run 'switch-commit use <profile>' first.",
                            json: options.json
                        )
                    case .invalidMode(let value):
                        CLIRuntime.terminate(
                            code: .usage,
                            message: "Mode must be 'folder-tree' or 'single-repo' (got '\(value)').",
                            json: options.json
                        )
                    }
                }

                let rule = try session.addFolderRule(
                    path: defaults.path,
                    profileReference: defaults.profileReference,
                    matchMode: defaults.matchMode,
                    moveIfOwned: yes
                )
                if options.json {
                    print(CLIOutput.jsonRules(rules: [rule]))
                } else {
                    let modeLabel = defaults.matchMode == .singleRepo ? "single-repo" : "folder-tree"
                    print("Added folder rule: \(rule.path) → \(rule.profileId) (\(modeLabel))")
                }
            } catch let error as FolderRuleMutationError {
                switch error {
                case .ownedByOtherProfile(let profileId):
                    CLIRuntime.terminate(
                        code: .usage,
                        message: "Folder is owned by profile '\(profileId)'. Pass --yes to take it over.",
                        json: options.json
                    )
                case .profileNotFound:
                    CLIRuntime.terminate(for: error, json: options.json)
                }
            } catch {
                CLIRuntime.terminate(for: error, json: options.json)
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
                let pathReference = reference.hasPrefix("~")
                    || reference.contains("/")
                    || reference.contains("\\")
                    || reference == "."
                let rule: FolderRule?
                if pathReference {
                    let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
                    let normalizedPath = FolderRuleResolver.normalize(
                        reference,
                        homeDirectory: homeDirectory
                    )
                    rule = session.rules.first {
                        FolderRuleResolver.normalize($0.path, homeDirectory: homeDirectory) == normalizedPath
                    }
                } else {
                    rule = session.rules.first { $0.id == reference || $0.path == reference }
                }
                guard let rule else {
                    CLIRuntime.terminate(
                        code: .usage,
                        message: "Folder rule '\(reference)' was not found.",
                        json: options.json
                    )
                }

                if !yes {
                    guard !options.json, CLITerminal.isStandardInputTTY else {
                        CLIRuntime.terminate(
                            code: .usage,
                            message: "Pass --yes to remove a folder rule without an interactive confirmation.",
                            json: options.json
                        )
                    }
                    print("Remove folder rule '\(rule.path)'? [y/N]: ", terminator: "")
                    CLITerminal.flushStandardOutput()
                    guard let response = readLine(), ["y", "yes"].contains(response.lowercased()) else {
                        print("Removal cancelled.")
                        return
                    }
                }

                if pathReference {
                    try session.removeFolderRule(path: reference)
                } else {
                    try session.removeFolderRule(id: rule.id)
                }
                print(options.json ? CLIOutput.jsonOK() : "Removed folder rule: \(rule.path)")
            } catch {
                CLIRuntime.terminate(for: error, json: options.json)
            }
        }
    }
}
