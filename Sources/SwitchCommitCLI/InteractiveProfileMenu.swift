import Foundation
import SwitchCommitCore

#if !os(Windows)
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
#endif

struct InteractiveProfileMenu {
    #if !os(Windows)
    private var terminal = RawTerminal()
    #endif

    mutating func run(session: SwitchCommitSession) throws {
        #if os(Windows)
        try runNumbered(session: session)
        #else
        try runTermios(session: session)
        #endif
    }
}

#if os(Windows)
extension InteractiveProfileMenu {
    /// Numbered, line-oriented profile menu for platforms without a portable raw-mode
    /// terminal API (Windows): list profiles, then `a` add, `d <n>` delete, `q` quit,
    /// or a bare number to switch to that profile.
    private mutating func runNumbered(session: SwitchCommitSession) throws {
        while true {
            let profiles = session.profiles.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }

            print("")
            print("switch-commit · profiles")
            if profiles.isEmpty {
                print("  No profiles configured.")
            } else {
                for (index, profile) in profiles.enumerated() {
                    let mark = session.activeProfile?.id == profile.id ? "*" : " "
                    print("  \(index + 1)) \(mark) \(profile.displayName)  <\(profile.gitUserEmail)>")
                }
            }
            print("  a) add   d <n>) delete   q) quit")
            print("Select: ", terminator: "")

            guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return
            }
            let selection = line.lowercased()

            if selection.isEmpty {
                continue
            }
            if selection == "q" {
                return
            }
            if selection == "a" {
                do {
                    if let profile = try promptForProfileNumbered(session: session) {
                        print("Added \(profile.displayName).")
                    } else {
                        print("Add cancelled.")
                    }
                } catch {
                    print(error.localizedDescription)
                }
                continue
            }
            if selection.hasPrefix("d ") {
                deleteNumbered(selection, profiles: profiles, session: session)
                continue
            }
            if let index = Int(line), profiles.indices.contains(index - 1) {
                let profile = profiles[index - 1]
                do {
                    try session.use(reference: profile.id)
                    print("Using \(profile.displayName).")
                } catch {
                    print(error.localizedDescription)
                }
                continue
            }
            print("Unknown selection: \(line)")
        }
    }

    private func deleteNumbered(_ selection: String, profiles: [GitProfile], session: SwitchCommitSession) {
        let indexText = selection.dropFirst(2).trimmingCharacters(in: .whitespaces)
        guard let index = Int(indexText), profiles.indices.contains(index - 1) else {
            print("Unknown profile number.")
            return
        }
        let profile = profiles[index - 1]
        print("Delete '\(profile.displayName)'? [y/N]: ", terminator: "")
        guard let response = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              response == "y" || response == "yes" else {
            print("Deletion cancelled.")
            return
        }
        do {
            try session.deleteProfile(reference: profile.id)
            print("Deleted \(profile.displayName).")
        } catch {
            print(error.localizedDescription)
        }
    }

    private func promptForProfileNumbered(session: SwitchCommitSession) throws -> GitProfile? {
        print("Add profile (leave the name empty to cancel).")
        print("Display name: ", terminator: "")
        guard let displayName = readLine(), !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        print("Git author name: ", terminator: "")
        guard let gitUserName = readLine(), !gitUserName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        print("Git author email: ", terminator: "")
        guard let gitUserEmail = readLine(), !gitUserEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return try session.addProfile(
            displayName: displayName,
            gitUserName: gitUserName,
            gitUserEmail: gitUserEmail,
            accessMethod: .https,
            sshKeyPath: "",
            hosts: ["github.com"]
        )
    }
}
#else
extension InteractiveProfileMenu {
    private enum Key {
        case up
        case down
        case enter
        case quit
        case delete
        case add
        case other
    }

    fileprivate enum TerminalError: Error {
        case readAttributes
        case setAttributes
    }

    /// Raw-mode, arrow-key-driven profile menu used on Darwin/Glibc where termios is available.
    private mutating func runTermios(session: SwitchCommitSession) throws {
        try terminal.enable()
        defer {
            terminal.restore()
            print("\u{001B}[?25h", terminator: "")
        }

        var selectedIndex = 0
        var message: String?

        while true {
            let profiles = session.profiles.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            selectedIndex = min(selectedIndex, max(profiles.count - 1, 0))
            draw(profiles: profiles, activeProfileID: session.activeProfile?.id, selectedIndex: selectedIndex, message: message)
            message = nil

            switch readKey() {
            case .up:
                selectedIndex = max(selectedIndex - 1, 0)
            case .down:
                selectedIndex = min(selectedIndex + 1, max(profiles.count - 1, 0))
            case .enter:
                guard profiles.indices.contains(selectedIndex) else { continue }
                do {
                    try session.use(reference: profiles[selectedIndex].id)
                    message = "Using \(profiles[selectedIndex].displayName)."
                } catch {
                    message = error.localizedDescription
                }
            case .delete:
                guard profiles.indices.contains(selectedIndex) else { continue }
                do {
                    let profile = profiles[selectedIndex]
                    if try confirm("Delete '\(profile.displayName)'? [y/N]: ") {
                        try session.deleteProfile(reference: profile.id)
                        selectedIndex = max(selectedIndex - 1, 0)
                        message = "Deleted \(profile.displayName)."
                    } else {
                        message = "Deletion cancelled."
                    }
                } catch {
                    message = error.localizedDescription
                }
            case .add:
                do {
                    if let profile = try promptForProfile(session: session) {
                        message = "Added \(profile.displayName)."
                    } else {
                        message = "Add cancelled."
                    }
                } catch {
                    message = error.localizedDescription
                }
            case .quit:
                return
            case .other:
                continue
            }
        }
    }

    private func draw(
        profiles: [GitProfile],
        activeProfileID: String?,
        selectedIndex: Int,
        message: String?
    ) {
        print("\u{001B}[2J\u{001B}[H\u{001B}[?25l", terminator: "")
        print("switch-commit · profiles")
        print("")
        if profiles.isEmpty {
            print("  No profiles configured.")
        } else {
            for (index, profile) in profiles.enumerated() {
                let cursor = index == selectedIndex ? "›" : " "
                let active = profile.id == activeProfileID ? "●" : " "
                print("\(cursor) \(active) \(profile.displayName)  <\(profile.gitUserEmail)>")
            }
        }
        print("")
        print("↑/↓ or j/k move · Enter use · a add · d delete · q quit")
        if let message {
            print("")
            print(message)
        }
        fflush(stdout)
    }

    private mutating func confirm(_ prompt: String) throws -> Bool {
        terminal.restore()
        defer { try? terminal.enable() }
        print("\u{001B}[?25h\(prompt)", terminator: "")
        fflush(stdout)
        let response = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return response == "y" || response == "yes"
    }

    private mutating func promptForProfile(session: SwitchCommitSession) throws -> GitProfile? {
        terminal.restore()
        defer { try? terminal.enable() }
        print("\u{001B}[2J\u{001B}[H\u{001B}[?25hAdd profile (leave the name empty to cancel).")
        print("Display name: ", terminator: "")
        fflush(stdout)
        guard let displayName = readLine(), !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        print("Git author name: ", terminator: "")
        fflush(stdout)
        guard let gitUserName = readLine(), !gitUserName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        print("Git author email: ", terminator: "")
        fflush(stdout)
        guard let gitUserEmail = readLine(), !gitUserEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return try session.addProfile(
            displayName: displayName,
            gitUserName: gitUserName,
            gitUserEmail: gitUserEmail,
            accessMethod: .https,
            sshKeyPath: "",
            hosts: ["github.com"]
        )
    }

    private func readKey() -> Key {
        var byte: UInt8 = 0
        guard read(STDIN_FILENO, &byte, 1) == 1 else { return .quit }
        switch byte {
        case 3, 113: return .quit
        case 10, 13: return .enter
        case 106: return .down
        case 107: return .up
        case 100: return .delete
        case 97: return .add
        case 27:
            var sequence = [UInt8]()
            for _ in 0..<2 {
                var next: UInt8 = 0
                guard read(STDIN_FILENO, &next, 1) == 1 else { break }
                sequence.append(next)
            }
            if sequence == [91, 65] { return .up }
            if sequence == [91, 66] { return .down }
            return .other
        default: return .other
        }
    }
}

private struct RawTerminal {
    private var original: termios?

    mutating func enable() throws {
        var attributes = termios()
        guard tcgetattr(STDIN_FILENO, &attributes) == 0 else {
            throw InteractiveProfileMenu.TerminalError.readAttributes
        }
        original = attributes

        var raw = attributes
        raw.c_lflag &= ~tcflag_t(ICANON | ECHO)
        raw.c_iflag &= ~tcflag_t(ICRNL | IXON)
        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else {
            throw InteractiveProfileMenu.TerminalError.setAttributes
        }
    }

    mutating func restore() {
        guard var original else { return }
        _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        self.original = nil
    }
}
#endif
