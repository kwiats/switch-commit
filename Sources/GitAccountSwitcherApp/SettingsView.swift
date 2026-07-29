import GitAccountSwitcherAppLogic
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Git Account Switcher")
                .font(.headline)

            GroupBox("Active Profile") {
                VStack(alignment: .leading, spacing: 6) {
                    if let activeProfile = viewModel.activeProfile {
                        Text(activeProfile.displayName)
                            .font(.body.weight(.medium))
                        Text(activeProfile.gitUserEmail)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No profile selected")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Diagnostics") {
                Text(viewModel.diagnosticsText)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(width: 460, height: 260)
    }
}
