import Foundation
import SwitchCommitAppLogic
import Sparkle

@MainActor
final class SparkleAppUpdateChecker: NSObject, AppUpdateChecking {
    private let updaterDelegate: ManualSparkleUpdaterDelegate
    private let updaterController: SPUStandardUpdaterController
    private var hasStartedUpdater = false

    var successfulUpdateCycleHandler: (() -> Void)? {
        get { updaterDelegate.successfulUpdateCycleHandler }
        set { updaterDelegate.successfulUpdateCycleHandler = newValue }
    }

    override init() {
        let createdUpdaterDelegate = ManualSparkleUpdaterDelegate()
        self.updaterDelegate = createdUpdaterDelegate
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: createdUpdaterDelegate,
            userDriverDelegate: nil
        )
        super.init()
    }

    var canCheckForUpdates: Bool {
        hasReleaseChannelConfiguration && (!hasStartedUpdater || updaterController.updater.canCheckForUpdates)
    }

    func checkForUpdates() {
        guard hasReleaseChannelConfiguration else {
            return
        }
        if !hasStartedUpdater {
            updaterController.updater.automaticallyChecksForUpdates = false
            updaterController.updater.automaticallyDownloadsUpdates = false
            updaterController.startUpdater()
            hasStartedUpdater = true
        }
        updaterController.checkForUpdates(nil)
    }

    private var hasReleaseChannelConfiguration: Bool {
        hasInfoValue(forKey: "SUFeedURL") && hasInfoValue(forKey: "SUPublicEDKey")
    }

    private func hasInfoValue(forKey key: String) -> Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return false
        }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private final class ManualSparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    var successfulUpdateCycleHandler: (() -> Void)?

    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
        false
    }

    func feedParameters(for updater: SPUUpdater, sendingSystemProfile sendingProfile: Bool) -> [[String: String]] {
        []
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        successfulUpdateCycleHandler?()
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        if shouldSyncCLI(afterCycleError: error) {
            successfulUpdateCycleHandler?()
        }
    }

    private func shouldSyncCLI(afterCycleError error: (any Error)?) -> Bool {
        guard let error else {
            return true
        }
        let nsError = error as NSError
        guard nsError.domain == SUSparkleErrorDomain else {
            return false
        }
        return nsError.code == Int(SUError.noUpdateError.rawValue)
    }
}
