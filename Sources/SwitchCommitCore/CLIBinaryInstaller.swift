import Crypto
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
@preconcurrency import Glibc
#endif
#if os(Windows)
import WinSDK
#endif

/// Downloads and installs `switch-commit` CLI portable binaries published on the
/// public GitHub release channel (used on Linux/Windows where there is no app DMG).
public struct CLIBinaryInstaller {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Downloads `remote` synchronously and writes it to `local`.
    public func download(_ remote: URL, to local: URL) throws {
        let data = try Data(contentsOf: remote)
        try fileManager.createDirectory(
            at: local.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: local, options: [.atomic])
    }

    /// Best-effort fetch of a `.sha256` sum file. Returns `nil` when the sum file is
    /// missing or unreadable so callers can skip verification without failing the update.
    public func readSHA256SumFile(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return Self.parseSHA256(from: text)
    }

    /// Parses the first 64-character hex token out of a `sha256sum`-style file
    /// (`"<hex>  filename"` or a bare hex digest).
    public static func parseSHA256(from text: String) -> String? {
        guard let token = text
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init)?
            .lowercased(),
            token.count == 64,
            token.allSatisfy(\.isHexDigit) else {
            return nil
        }
        return token
    }

    /// Throws `.checksumMismatch` when the computed SHA-256 of `fileURL` does not match `expectedHex`.
    public func verifySHA256(fileURL: URL, expectedHex: String) throws {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
        let actual = digest.map { String(format: "%02x", $0) }.joined()
        let expected = expectedHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard actual == expected else {
            throw CLIBinaryInstallerError.checksumMismatch
        }
    }

    /// Resolves the currently running executable, following one level of symlink
    /// (mirrors `CLIVersion`'s handling of `/usr/local/bin` stubs).
    ///
    /// Prefers an OS-native lookup of the running process's own executable path
    /// (`/proc/self/exe` on Linux, `_NSGetExecutablePath` on macOS,
    /// `GetModuleFileNameW` on Windows), because that is authoritative
    /// regardless of how the binary was invoked — including a bare
    /// `switch-commit` launched via `PATH`, where `argument0` alone is not a
    /// valid filesystem path. Falls back to resolving `argument0` (used as-is
    /// when it contains a path separator, or searched for on `PATH` via
    /// `ProcessLaunchPath` when it is a bare name) when the native lookup is
    /// unavailable, or explicitly disabled — as tests do, to exercise the
    /// `PATH`-search fallback in isolation.
    public func resolveRunningExecutable(
        argument0: String? = CommandLine.arguments.first,
        nativeExecutablePath: String? = CLIBinaryInstaller.nativeExecutablePath()
    ) throws -> URL {
        var candidate: URL?

        if let nativeExecutablePath, fileManager.fileExists(atPath: nativeExecutablePath) {
            candidate = URL(fileURLWithPath: nativeExecutablePath).standardizedFileURL
        }

        if candidate == nil, let argument0, !argument0.isEmpty {
            if argument0.contains("/") || argument0.contains("\\") {
                candidate = URL(fileURLWithPath: argument0).standardizedFileURL
            } else if let resolved = ProcessLaunchPath.executableURL(for: argument0, fileManager: fileManager),
                      resolved.path != "/usr/bin/env" {
                // `ProcessLaunchPath` falls back to `/usr/bin/env` as a generic process-spawning
                // sentinel when `argument0` isn't found on PATH; that's meaningless here, where we
                // need the actual on-disk executable to replace, so treat it as "not found".
                candidate = resolved.standardizedFileURL
            }
        }

        guard let candidate else {
            throw CLIBinaryInstallerError.cannotLocateRunningExecutable
        }

        let resolved = resolveSymlink(candidate)
        guard fileManager.fileExists(atPath: resolved.path) else {
            throw CLIBinaryInstallerError.cannotLocateRunningExecutable
        }
        return resolved
    }

    private func resolveSymlink(_ url: URL) -> URL {
        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) {
            return URL(fileURLWithPath: destination, relativeTo: url.deletingLastPathComponent())
                .standardizedFileURL
        }
        return url
    }

    /// Best-effort OS-native lookup of the currently running process's own
    /// executable path. `nil` when unsupported/unavailable, in which case
    /// callers fall back to `argument0`-based resolution.
    public static func nativeExecutablePath() -> String? {
        #if os(Linux)
        return linuxProcSelfExecutablePath()
        #elseif os(Windows)
        return windowsModuleFileNamePath()
        #elseif canImport(Darwin)
        return darwinExecutablePath()
        #else
        return nil
        #endif
    }

    #if os(Linux)
    private static func linuxProcSelfExecutablePath() -> String? {
        var buffer = [Int8](repeating: 0, count: 4096)
        let length = readlink("/proc/self/exe", &buffer, buffer.count)
        guard length > 0, length < buffer.count else {
            return nil
        }
        return buffer.withUnsafeBufferPointer { pointer in
            pointer.baseAddress.map { String(cString: $0) }
        }
    }
    #endif

    #if canImport(Darwin)
    private static func darwinExecutablePath() -> String? {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        guard size > 0 else {
            return nil
        }
        var buffer = [Int8](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else {
            return nil
        }
        return buffer.withUnsafeBufferPointer { pointer in
            pointer.baseAddress.map { String(cString: $0) }
        }
    }
    #endif

    #if os(Windows)
    private static func windowsModuleFileNamePath() -> String? {
        let capacity = Int(MAX_PATH) + 1
        var buffer = [WCHAR](repeating: 0, count: capacity)
        let length = GetModuleFileNameW(nil, &buffer, DWORD(capacity))
        guard length > 0, Int(length) < capacity else {
            return nil
        }
        return String(decodingCString: buffer, as: UTF16.self)
    }
    #endif

    /// Atomically replaces `destination` with `source`, keeping a `.bak` copy until the
    /// swap succeeds so a failure never leaves the CLI without a working executable.
    ///
    /// When `version` is provided, a sibling `VERSION` file is written next to `destination`
    /// on success, so `CLIVersion.current()` can report the installed version on Linux/Windows
    /// where there is no app bundle `Info.plist` to read from.
    public func replaceExecutable(at destination: URL, with source: URL, version: String? = nil) throws {
        guard fileManager.fileExists(atPath: source.path) else {
            throw CLIBinaryInstallerError.assetMissing
        }

        let backup = destination.appendingPathExtension("bak")
        if fileManager.fileExists(atPath: backup.path) {
            try fileManager.removeItem(at: backup)
        }
        let destinationExisted = fileManager.fileExists(atPath: destination.path)
        if destinationExisted {
            try fileManager.moveItem(at: destination, to: backup)
        }

        do {
            try fileManager.copyItem(at: source, to: destination)
            #if !os(Windows)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
            #endif
            if destinationExisted {
                try? fileManager.removeItem(at: backup)
            }
            if let version {
                writeVersionFile(version, nextTo: destination)
            }
        } catch {
            if destinationExisted {
                try? fileManager.removeItem(at: destination)
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }
    }

    /// Best-effort write of a plain-text `VERSION` file next to `destination`. Failure here
    /// (e.g. an unwritable directory) must not fail an otherwise-successful binary replace.
    private func writeVersionFile(_ version: String, nextTo destination: URL) {
        let versionFile = destination.deletingLastPathComponent().appendingPathComponent("VERSION")
        try? version.write(to: versionFile, atomically: true, encoding: .utf8)
    }
}

public enum CLIBinaryInstallerError: LocalizedError, Equatable {
    case checksumMismatch
    case assetMissing
    case cannotLocateRunningExecutable

    public var errorDescription: String? {
        switch self {
        case .checksumMismatch:
            return "Downloaded CLI binary failed SHA-256 verification."
        case .assetMissing:
            return "No CLI binary asset is available for this platform/architecture."
        case .cannotLocateRunningExecutable:
            return "Could not locate the running switch-commit executable to replace."
        }
    }
}
