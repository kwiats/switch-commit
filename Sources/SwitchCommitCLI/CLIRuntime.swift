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

    static func style(json: Bool, noColor: Bool) -> CLIOutput.Style {
        CLIOutput.Style.detect(
            noColorFlag: json || noColor,
            isTTY: isatty(STDOUT_FILENO) != 0
        )
    }

    static func terminate(code: CLIExitCode, message: String?, json: Bool) -> Never {
        if let message {
            let output = json ? CLIOutput.jsonError(message) : message
            FileHandle.standardError.write(Data("\(output)\n".utf8))
        }
        exit(code.rawValue)
    }
}
