import Foundation
import GitAccountSwitcherAppLogic
import Sparkle

@MainActor
final class SparkleAppUpdateChecker: NSObject, AppUpdateChecking {
    private let updaterDelegate: ManualSparkleUpdaterDelegate
    private let updaterController: SPUStandardUpdaterController
    private var hasStartedUpdater = false

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
        false
    }

    func checkForUpdates() {
        if !hasStartedUpdater {
            updaterController.updater.automaticallyChecksForUpdates = false
            updaterController.updater.automaticallyDownloadsUpdates = false
            updaterController.startUpdater()
            hasStartedUpdater = true
        }
        updaterController.checkForUpdates(nil)
    }
}

private final class ManualSparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
        false
    }

    func feedParameters(for updater: SPUUpdater, sendingSystemProfile sendingProfile: Bool) -> [[String: String]] {
        []
    }
}
