import Crypto
import Foundation

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
    public func resolveRunningExecutable(argument0: String? = CommandLine.arguments.first) throws -> URL {
        guard let argument0 else {
            throw CLIBinaryInstallerError.cannotLocateRunningExecutable
        }
        let url = URL(fileURLWithPath: argument0).standardizedFileURL
        let resolved: URL
        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) {
            resolved = URL(fileURLWithPath: destination, relativeTo: url.deletingLastPathComponent())
                .standardizedFileURL
        } else {
            resolved = url
        }
        guard fileManager.fileExists(atPath: resolved.path) else {
            throw CLIBinaryInstallerError.cannotLocateRunningExecutable
        }
        return resolved
    }

    /// Atomically replaces `destination` with `source`, keeping a `.bak` copy until the
    /// swap succeeds so a failure never leaves the CLI without a working executable.
    public func replaceExecutable(at destination: URL, with source: URL) throws {
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
        } catch {
            if destinationExisted {
                try? fileManager.removeItem(at: destination)
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }
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
