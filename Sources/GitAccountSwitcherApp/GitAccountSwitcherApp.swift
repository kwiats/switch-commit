import GitAccountSwitcherCore
import SwiftUI

@main
struct GitAccountSwitcherApp: App {
    var body: some Scene {
        MenuBarExtra("Git Account Switcher", systemImage: "person.crop.circle.badge.checkmark") {
            Text("No profile selected")
            Divider()
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
                Text("Profiles and diagnostics will appear here.")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(width: 420, height: 220)
        }
    }
}
