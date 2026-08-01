import AppKit
import SwitchCommitAppLogic
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(viewModel: AppViewModel) {
        let hostingController = NSHostingController(rootView: SettingsView(viewModel: viewModel))

        if let window {
            window.contentViewController = hostingController
        } else {
            let createdWindow = NSWindow(contentViewController: hostingController)
            createdWindow.title = "Switch Commit Settings"
            createdWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            createdWindow.minSize = NSSize(width: 720, height: 440)
            createdWindow.setContentSize(NSSize(width: 900, height: 560))
            createdWindow.isReleasedWhenClosed = false
            createdWindow.center()
            window = createdWindow
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
