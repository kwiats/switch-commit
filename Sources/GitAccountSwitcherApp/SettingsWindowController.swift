import AppKit
import GitAccountSwitcherAppLogic
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(viewModel: AppViewModel) {
        if window == nil {
            let hostingController = NSHostingController(rootView: SettingsView(viewModel: viewModel))
            let createdWindow = NSWindow(contentViewController: hostingController)
            createdWindow.title = "Git Account Switcher Settings"
            createdWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            createdWindow.isReleasedWhenClosed = false
            createdWindow.center()
            window = createdWindow
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
