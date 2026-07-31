import Foundation
import SwitchCommitAppLogic

@MainActor
final class FrontmostContextMonitor {
    private let viewModel: AppViewModel
    private let provider: FrontmostPathProviding
    private var timer: Timer?

    init(viewModel: AppViewModel, provider: FrontmostPathProviding) {
        self.viewModel = viewModel
        self.provider = provider
    }

    func start() {
        guard timer == nil else {
            return
        }

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        if let result = provider.currentFrontmostPath(),
           let path = standardizedAbsolutePath(result.path) {
            viewModel.applyFrontmostPath(path, source: result.source)
        } else if provider.frontmostIsSupportedContextApp {
            viewModel.applyFrontmostUnavailable(reason: "Could not read folder")
        } else {
            viewModel.applyFrontmostClearedToGlobal()
        }
    }

    private func standardizedAbsolutePath(_ path: String) -> String? {
        guard path.hasPrefix("/") else {
            return nil
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
