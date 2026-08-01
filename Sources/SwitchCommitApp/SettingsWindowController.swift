import AppKit
import SwitchCommitAppLogic
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(viewModel: AppViewModel) {
        if window == nil {
            let hostingController = NSHostingController(rootView: SettingsView(viewModel: viewModel))
            let createdWindow = NSWindow(contentViewController: hostingController)
            createdWindow.title = "Switch Commit Settings"
            createdWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            createdWindow.minSize = NSSize(width: 640, height: 420)
            createdWindow.isReleasedWhenClosed = false
            createdWindow.center()
            window = createdWindow
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
