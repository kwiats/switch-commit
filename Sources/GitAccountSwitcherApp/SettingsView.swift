import AppKit
import GitAccountSwitcherAppLogic
import GitAccountSwitcherCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            accountList
                .frame(width: 220)
            Divider()
            accountDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 700, height: 440)
        .alert(DeleteAccountConfirmationContent.title, isPresented: $isShowingDeleteConfirmation) {
            Button(DeleteAccountConfirmationContent.confirmButtonTitle, role: .destructive) {
                viewModel.deleteSelectedProfile()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(DeleteAccountConfirmationContent.message)
        }
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
                    isShowingDeleteConfirmation = true
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
                detectedAccountsSection
                Spacer()
                footer
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    emptyState
                    detectedAccountsSection
                }
            }
        }
        .padding(20)
    }

    private var detectedAccountsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Detected Accounts")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.refreshDetectedAccounts()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Detect local GitHub accounts")
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        viewModel.scanSelectedFolderForGitHubAccounts(url)
                    }
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                }
                .help("Scan a folder for GitHub accounts")
            }

            if viewModel.detectedAccounts.isEmpty {
                Text("No local GitHub account was detected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.detectedAccounts) { account in
                            HStack(alignment: .center, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.username ?? account.gitUserName ?? "GitHub Account")
                                        .lineLimit(1)
                                    Text(detectedAccountSubtitle(account))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(account.confidence.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if account.gitUserEmail == nil {
                                    Button {
                                        viewModel.completeDetectedAccount(id: account.id)
                                    } label: {
                                        Label("Complete", systemImage: "square.and.pencil")
                                    }
                                    .help("Complete this detected account before importing")
                                } else {
                                    Button {
                                        viewModel.importDetectedAccount(id: account.id)
                                    } label: {
                                        Label("Add", systemImage: "plus.circle")
                                    }
                                    .help("Add detected account")
                                }
                            }
                            .padding(8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(minHeight: 0, maxHeight: 88)
            }
        }
    }

    private func detectedAccountSubtitle(_ account: DetectedGitAccount) -> String {
        if let email = account.gitUserEmail {
            return email
        }
        if account.warnings.isEmpty {
            return "Local GitHub configuration found"
        }
        return account.warnings[0]
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
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
