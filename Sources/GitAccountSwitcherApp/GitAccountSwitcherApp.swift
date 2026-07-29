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
            SettingsView(viewModel: viewModel)
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 0) {
            accountList
                .frame(width: 220)
            Divider()
            accountDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 700, height: 440)
    }

    private var accountList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Accounts")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.addProfile()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add account")
                .buttonStyle(.borderless)
            }
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 8)

            List(selection: Binding(
                get: { viewModel.selectedProfileId },
                set: { viewModel.selectProfile(id: $0) }
            )) {
                ForEach(viewModel.profiles) { profile in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.displayName)
                            .lineLimit(1)
                        Text(profile.gitUserEmail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(Optional(profile.id))
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
                Button(role: .destructive) {
                    viewModel.deleteSelectedProfile()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete selected account")
                .disabled(viewModel.selectedProfile == nil)
                .buttonStyle(.borderless)

                Spacer()

                if let activeProfile = viewModel.activeProfile {
                    Text("Active: \(activeProfile.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
        }
    }

    private var accountDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let profile = viewModel.selectedProfile {
                header(for: profile)
                accountForm
                Spacer()
                footer
            } else {
                emptyState
            }
        }
        .padding(20)
    }

    private func header(for profile: GitProfile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(profile.displayName)
                .font(.title2)
                .lineLimit(1)
            Text(profile.gitUserEmail)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var accountForm: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Text("Display name")
                    .foregroundStyle(.secondary)
                TextField("Display name", text: Binding(
                    get: { viewModel.selectedProfile?.displayName ?? "" },
                    set: { viewModel.updateSelectedProfileDisplayName($0) }
                ))
            }
            GridRow {
                Text("Git name")
                    .foregroundStyle(.secondary)
                TextField("Git name", text: Binding(
                    get: { viewModel.selectedProfile?.gitUserName ?? "" },
                    set: { viewModel.updateSelectedProfileGitUserName($0) }
                ))
            }
            GridRow {
                Text("Git email")
                    .foregroundStyle(.secondary)
                TextField("Git email", text: Binding(
                    get: { viewModel.selectedProfile?.gitUserEmail ?? "" },
                    set: { viewModel.updateSelectedProfileGitUserEmail($0) }
                ))
            }
            GridRow {
                Text("SSH key")
                    .foregroundStyle(.secondary)
                TextField("SSH key", text: Binding(
                    get: { viewModel.selectedProfile?.sshKeyPath ?? "" },
                    set: { viewModel.updateSelectedProfileSSHKeyPath($0) }
                ))
            }
            GridRow {
                Text("Hosts")
                    .foregroundStyle(.secondary)
                TextField("Hosts", text: Binding(
                    get: { viewModel.hostsTextForSelectedProfile },
                    set: { viewModel.updateSelectedProfileHostsText($0) }
                ))
            }
            GridRow {
                Text("Access")
                    .foregroundStyle(.secondary)
                HStack {
                    Button {
                        viewModel.resetAccessForSelectedProfile()
                    } label: {
                        Label("Reset Access", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(viewModel.selectedProfile == nil)
                    Spacer()
                    if viewModel.selectedProfile?.httpsCredentialRef == nil {
                        Text("No HTTPS credential stored")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let settingsMessage = viewModel.settingsMessage {
                Text(settingsMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Text(viewModel.diagnosticsText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No Account Selected")
                .font(.title2)
            Text("Add an account to configure Git identity, SSH key, hosts, and local access.")
                .foregroundStyle(.secondary)
            Button {
                viewModel.addProfile()
            } label: {
                Label("Add Account", systemImage: "plus")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
