import AppKit
import CoreGraphics
import Foundation
import SwitchCommitAppLogic

final class LiveFrontmostPathProvider: FrontmostPathProviding {
    private var frontmostApplication: NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }

    var frontmostIsSupportedContextApp: Bool {
        guard let application = frontmostApplication else {
            return false
        }
        return Self.source(for: application) != nil
    }

    func currentFrontmostPath() -> (path: String, source: FrontmostPathSource)? {
        guard
            let application = frontmostApplication,
            let source = Self.source(for: application)
        else {
            return nil
        }

        let path: String?
        switch source {
        case .finder:
            path = Self.finderPath()
        case .terminal:
            path = Self.terminalPath()
        case .iterm:
            path = Self.iTermPath()
        case .cursor, .vsCode:
            path = Self.editorPath(for: application)
        }

        guard let path = Self.standardizedAbsolutePath(path) else {
            return nil
        }
        return (path, source)
    }

    private static func source(for application: NSRunningApplication) -> FrontmostPathSource? {
        switch application.bundleIdentifier {
        case "com.apple.finder":
            .finder
        case "com.apple.Terminal":
            .terminal
        case "com.googlecode.iterm2":
            .iterm
        case "com.todesktop.230313mzl4w4u92", "com.cursor.Cursor":
            .cursor
        case "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders":
            .vsCode
        default:
            nil
        }
    }

    private static func finderPath() -> String? {
        runAppleScript("""
        tell application "Finder"
            POSIX path of (target of front window as alias)
        end tell
        """)
    }

    private static func terminalPath() -> String? {
        guard let tty = runAppleScript("""
        tell application "Terminal"
            tty of selected tab of front window
        end tell
        """) else {
            return nil
        }
        return workingDirectory(forTTY: tty)
    }

    private static func iTermPath() -> String? {
        runAppleScript("""
        tell application "iTerm2"
            tell current session of current window
                get variable named "path"
            end tell
        end tell
        """)
    }

    private static func editorPath(for application: NSRunningApplication) -> String? {
        let titles = windowTitles(forProcessID: application.processIdentifier)
        for title in titles {
            if let path = absolutePath(in: title) {
                return path
            }
        }
        return nil
    }

    private static func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else {
            return nil
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else {
            return nil
        }
        return result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func workingDirectory(forTTY tty: String) -> String? {
        let ttyPath = tty.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ttyPath.hasPrefix("/") else {
            return nil
        }
        return runLocalCommand(
            executablePath: "/usr/sbin/lsof",
            arguments: ["-a", "-d", "cwd", "-Fn", ttyPath]
        )?
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("n/") })
            .map { String($0.dropFirst()) }
    }

    private static func runLocalCommand(executablePath: String, arguments: [String]) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }

    private static func windowTitles(forProcessID processID: pid_t) -> [String] {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return windows.compactMap { window in
            guard
                window[kCGWindowOwnerPID as String] as? pid_t == processID,
                let title = window[kCGWindowName as String] as? String
            else {
                return nil
            }
            return title
        }
    }

    private static func absolutePath(in title: String) -> String? {
        guard let slash = title.firstIndex(of: "/") else {
            return nil
        }
        let suffix = String(title[slash...])
        let candidate = [" — ", " – ", " - "]
            .compactMap { suffix.range(of: $0).map { String(suffix[..<$0.lowerBound]) } }
            .first ?? suffix
        let trimmed = candidate.trimmingCharacters(
            in: .whitespacesAndNewlines.union(.init(charactersIn: "\"'"))
        )
        return standardizedAbsolutePath(trimmed)
    }

    private static func standardizedAbsolutePath(_ path: String?) -> String? {
        guard let path, path.hasPrefix("/") else {
            return nil
        }
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: standardized) else {
            return nil
        }
        return standardized
    }
}
