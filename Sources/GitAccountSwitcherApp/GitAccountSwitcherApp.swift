import GitAccountSwitcherCore
import SwiftUI

@main
struct GitAccountSwitcherApp: App {
    @StateObject private var viewModel = AppViewModel()

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
            }
            Button("Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }

        Settings {
            VStack(alignment: .leading, spacing: 12) {
                Text("Git Account Switcher")
                    .font(.headline)
                if let activeProfile = viewModel.activeProfile {
                    Text("Active profile: \(activeProfile.displayName)")
                    Text(activeProfile.gitUserEmail)
                        .foregroundStyle(.secondary)
                }
                Divider()
                Text(viewModel.diagnosticsText)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(width: 420, height: 220)
        }
    }
}
