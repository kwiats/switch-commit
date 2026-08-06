import Foundation

#if os(Windows)
import ucrt
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Centralizes TTY detection so command implementations never branch on
/// platform-specific `isatty` symbols themselves (Darwin, Glibc, or the
/// Windows Universal CRT).
enum CLITerminal {
    static var isStandardInputTTY: Bool {
        #if os(Windows)
        return _isatty(_fileno(stdin)) != 0
        #elseif canImport(Darwin)
        return Darwin.isatty(Darwin.STDIN_FILENO) != 0
        #elseif canImport(Glibc)
        return Glibc.isatty(Glibc.STDIN_FILENO) != 0
        #else
        return false
        #endif
    }

    static var isStandardOutputTTY: Bool {
        #if os(Windows)
        return _isatty(_fileno(stdout)) != 0
        #elseif canImport(Darwin)
        return Darwin.isatty(Darwin.STDOUT_FILENO) != 0
        #elseif canImport(Glibc)
        return Glibc.isatty(Glibc.STDOUT_FILENO) != 0
        #else
        return false
        #endif
    }

    /// True when both standard input and standard output are attached to a terminal.
    static var isInteractive: Bool {
        isStandardInputTTY && isStandardOutputTTY
    }

    /// Flushes stdout so prompts appear before `readLine()` (portable across Darwin/Glibc/Windows).
    static func flushStandardOutput() {
        #if os(Windows)
        // `stdout` is not consistently visible to Swift as a global on Windows CRT imports;
        // flush all open C streams instead.
        _ = fflush(nil)
        #elseif canImport(Darwin)
        fflush(Darwin.stdout)
        #elseif canImport(Glibc)
        fflush(Glibc.stdout)
        #else
        try? FileHandle.standardOutput.synchronize()
        #endif
    }
}
