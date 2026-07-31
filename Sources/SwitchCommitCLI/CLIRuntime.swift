import Foundation
import SwitchCommitCore

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum CLIRuntime {
    static func session() throws -> SwitchCommitSession {
        try SwitchCommitSession.live()
    }

    static func terminate(for error: Error, json: Bool) -> Never {
        if let error = error as? ProfileReferenceError {
            terminate(
                code: .usage,
                message: profileReferenceMessage(for: error),
                json: json
            )
        }

        terminate(
            code: .failure,
            message: error.localizedDescription,
            json: json
        )
    }

    static func style(json: Bool, noColor: Bool) -> CLIOutput.Style {
        CLIOutput.Style.detect(
            noColorFlag: json || noColor,
            isTTY: isatty(STDOUT_FILENO) != 0
        )
    }

    static func terminate(code: CLIExitCode, message: String?, json: Bool) -> Never {
        if let message {
            let output = json ? CLIOutput.jsonError(message) : message
            let handle = json ? FileHandle.standardOutput : FileHandle.standardError
            handle.write(Data("\(output)\n".utf8))
        }
        exit(code.rawValue)
    }

    private static func profileReferenceMessage(for error: ProfileReferenceError) -> String {
        switch error {
        case .notFound(let reference):
            return "Profile '\(reference)' was not found."
        case .ambiguous(let reference, let candidates):
            return "Profile reference '\(reference)' is ambiguous. Matches: \(candidates.joined(separator: ", "))."
        }
    }
}
