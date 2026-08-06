import Foundation

public enum CLIReleaseOS: String, Sendable {
    case linux
    case windows
    case macOS
}

public enum CLIReleaseArch: String, Sendable {
    case x86_64
    case arm64
}

public enum CLIReleaseAsset: Sendable {
    /// GitHub `owner/repo` for release assets (public Releases host).
    public static let defaultRepository = "kwiats/switch-commit"

    public static func currentOS() -> CLIReleaseOS {
        #if os(Windows)
        return .windows
        #elseif os(Linux)
        return .linux
        #else
        return .macOS
        #endif
    }

    public static func currentArch() -> CLIReleaseArch {
        #if arch(arm64)
        return .arm64
        #else
        return .x86_64
        #endif
    }

    public static func fileName(os: CLIReleaseOS, arch: CLIReleaseArch) -> String {
        switch os {
        case .windows:
            return "switch-commit-windows-\(arch.rawValue).exe"
        case .linux:
            return "switch-commit-linux-\(arch.rawValue)"
        case .macOS:
            return "switch-commit-macos-\(arch.rawValue)"
        }
    }

    public static func downloadURL(
        version: String,
        os: CLIReleaseOS,
        arch: CLIReleaseArch,
        repository: String = CLIReleaseAsset.defaultRepository
    ) -> URL {
        let tag = version.hasPrefix("v") ? version : "v\(version)"
        let name = fileName(os: os, arch: arch)
        return URL(string: "https://github.com/\(repository)/releases/download/\(tag)/\(name)")!
    }

    public static func sha256URL(for binaryURL: URL) -> URL {
        URL(string: binaryURL.absoluteString + ".sha256")!
    }
}
