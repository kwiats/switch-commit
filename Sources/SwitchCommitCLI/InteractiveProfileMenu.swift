import Foundation
import SwitchCommitCore

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct InteractiveProfileMenu {
    private enum Key {
        case up
        case down
        case enter
        case quit
        case delete
        case add
        case other
    }

    private enum TerminalError: Error {
        case readAttributes
        case setAttributes
    }

    private var terminal = RawTerminal()

    mutating func run(session: SwitchCommitSession) throws {
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

    private struct RawTerminal {
        private var original: termios?

        mutating func enable() throws {
            var attributes = termios()
            guard tcgetattr(STDIN_FILENO, &attributes) == 0 else {
                throw TerminalError.readAttributes
            }
            original = attributes

            var raw = attributes
            raw.c_lflag &= ~tcflag_t(ICANON | ECHO)
            raw.c_iflag &= ~tcflag_t(ICRNL | IXON)
            guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else {
                throw TerminalError.setAttributes
            }
        }

        mutating func restore() {
            guard var original else { return }
            _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
            self.original = nil
        }
    }
}
