import ArgumentParser
import Foundation
import SwitchCommitCore
#if canImport(Darwin)
import Darwin
#endif

private func emitCLIUpdateNoticeOnExit() {
    let args = CommandLine.arguments
    if args.contains("--json") || args.contains("update") {
        return
    }
    CLIRuntime.emitUpdateNoticeIfNeeded(json: false)
}

#if canImport(Darwin)
atexit(emitCLIUpdateNoticeOnExit)
#endif

SwitchCommitCommand.main()
