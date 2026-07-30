import Foundation
import GitAccountSwitcherAppLogic
import ServiceManagement

struct SystemLaunchAtLoginManager: LaunchAtLoginManaging {
    var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .unavailable(message: "Launch at login requires approval in System Settings.")
        case .notFound:
            return .unavailable(message: "Launch at login is unavailable for this app build.")
        @unknown default:
            return .unavailable(message: "Launch at login status is unavailable.")
        }
    }

    func enable() throws {
        try SMAppService.mainApp.register()
    }

    func disable() throws {
        try SMAppService.mainApp.unregister()
    }
}
