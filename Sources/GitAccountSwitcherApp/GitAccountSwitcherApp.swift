import GitAccountSwitcherAppLogic
import GitAccountSwitcherCore
import SwiftUI

@main
struct GitAccountSwitcherApp: App {
    @StateObject private var viewModel = AppViewModel()
    @State private var settingsWindowController = SettingsWindowController()

    var body: some Scene {
        MenuBarExtra("Git Account Switcher", systemImage: "person.crop.circle.badge.checkmark") {
            if let activeProfile = viewModel.activeProfile {
                Text("Active: \(activeProfile.displayName)")
                Divider()
                ForEach(viewModel.profiles) { profile in
                    Button(profile.displayName) {
                        viewModel.switchGlobalProfile(to: profile)
                    }
                }
            } else {
                Text("No profile selected")
            }
            Divider()
            Button("Run Local Diagnostics") {
                viewModel.runLocalDiagnostics()
                presentRequestedWindow()
            }
            Button("Settings") {
                viewModel.requestSettingsPresentation()
                presentRequestedWindow()
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func presentRequestedWindow() {
        guard viewModel.presentationRequest == .settings else {
            return
        }
        settingsWindowController.show(viewModel: viewModel)
        viewModel.clearPresentationRequest()
    }
}
