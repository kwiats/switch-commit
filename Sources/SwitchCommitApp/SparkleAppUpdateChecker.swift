import Foundation
import SwitchCommitAppLogic
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
    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
        false
    }

    func feedParameters(for updater: SPUUpdater, sendingSystemProfile sendingProfile: Bool) -> [[String: String]] {
        []
    }
}
