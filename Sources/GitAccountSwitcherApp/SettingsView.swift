import AppKit
import GitAccountSwitcherAppLogic
import GitAccountSwitcherCore
import SwiftUI

struct SettingsView: View {
    private enum SettingsTab: Hashable {
        case general
        case accounts
        case detection
        case updates
    }

    @ObservedObject var viewModel: AppViewModel
    @State private var isShowingDeleteConfirmation = false
    @State private var selectedTab: SettingsTab = .accounts

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)

            accountsTab
                .tabItem {
                    Label("Accounts", systemImage: "person.2")
                }
                .tag(SettingsTab.accounts)

            detectionTab
                .tabItem {
                    Label("Detection", systemImage: "magnifyingglass")
                }
                .tag(SettingsTab.detection)

            updatesTab
                .tabItem {
                    Label("Updates", systemImage: "arrow.down.circle")
                }
                .tag(SettingsTab.updates)
        }
        .frame(width: 760, height: 500)
        .alert(DeleteAccountConfirmationContent.title, isPresented: $isShowingDeleteConfirmation) {
            Button(DeleteAccountConfirmationContent.confirmButtonTitle, role: .destructive) {
                viewModel.deleteSelectedProfile()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(DeleteAccountConfirmationContent.message)
        }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General")
                .font(.title2)

            Toggle(isOn: Binding(
                get: { viewModel.isLaunchAtLoginEnabled },
                set: { viewModel.setLaunchAtLoginEnabled($0) }
            )) {
                Label("Launch at Login", systemImage: "power")
            }
            .toggleStyle(.switch)

            Text(viewModel.launchAtLoginStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
            footer
        }
        .padding(20)
    }

    private var accountsTab: some View {
        HStack(spacing: 0) {
            accountList
                .frame(width: 220)
            Divider()
            accountDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.providerSystemImageName(for: profile))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Image(systemName: viewModel.connectionStatus(for: profile).systemImageName)
                            .font(.system(size: 8))
                            .foregroundStyle(statusColor(viewModel.connectionStatus(for: profile)))
                            .frame(width: 10)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(profile.displayName)
                                .lineLimit(1)
                            Text(profile.gitUserEmail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
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
                Spacer()
                footer
            } else {
                emptyState
            }
        }
        .padding(20)
    }

    private var detectionTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Account Detection")
                    .font(.title2)
                Text("Find local GitHub account suggestions from Git, SSH, GitHub CLI, and a folder you choose.")
                    .foregroundStyle(.secondary)
            }

            detectedAccountsSection
            Spacer()
            footer
        }
        .padding(20)
    }

    private var updatesTab: some View {
        let presentation = viewModel.updatePresentation
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.productName)
                    .font(.title2)
                Text("Version \(presentation.installedVersion)")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button {
                        viewModel.checkForUpdates()
                    } label: {
                        Label("Check for Updates", systemImage: "arrow.clockwise")
                    }
                    .disabled(!presentation.canCheckForUpdates)

                    Spacer()
                }

                Text(presentation.privacyNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
            footer
        }
        .padding(20)
    }

    private var detectedAccountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("No local GitHub account was detected.")
                    Text("Use local detection or scan a repository folder to look for account hints.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.detectedAccounts) { account in
                            detectedAccountRow(account)
                        }
                    }
                }
                .frame(minHeight: 260)
            }
        }
    }

    private func detectedAccountRow(_ account: DetectedGitAccount) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(account.username ?? account.gitUserName ?? "GitHub Account")
                    .font(.headline)
                    .lineLimit(1)
                Text(detectedAccountSubtitle(account))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    metadataLabel("Provider: \(providerLabel(account.provider))", systemImage: "person.crop.circle")
                    metadataLabel("Access: \(accessMethodsText(account.accessMethods))", systemImage: "key")
                    metadataLabel("Sources: \(detectionSourcesText(account.sources))", systemImage: "point.3.connected.trianglepath.dotted")
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
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
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func metadataLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
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

    private func providerLabel(_ provider: GitAccountProvider) -> String {
        switch provider {
        case .github:
            return "GitHub"
        }
    }

    private func accessMethodsText(_ methods: [GitAccessMethod]) -> String {
        if methods.isEmpty {
            return "Choose during import"
        }
        return methods.map { method in
            switch method {
            case .ssh:
                return "SSH"
            case .https:
                return "HTTPS"
            }
        }.joined(separator: ", ")
    }

    private func detectionSourcesText(_ sources: [DetectionSource]) -> String {
        let labels = sources.map(detectionSourceLabel)
        if labels.isEmpty {
            return "Unknown source"
        }
        return labels.joined(separator: ", ")
    }

    private func detectionSourceLabel(_ source: DetectionSource) -> String {
        switch source {
        case .githubCliHostsFile, .githubCliInstalled:
            return "GitHub CLI"
        case .globalGitConfig:
            return "Global Git config"
        case .gitCredentialUsername:
            return "Git credentials"
        case .sshConfig:
            return "SSH config"
        case .sshResolvedConfig:
            return "SSH resolved config"
        case .repositoryRemote:
            return "Repository remote"
        }
    }

    private func header(for profile: GitProfile) -> some View {
        let status = viewModel.connectionStatus(for: profile)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: viewModel.providerSystemImageName(for: profile))
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(profile.displayName)
                    .font(.title2)
                    .lineLimit(1)
                Text(profile.gitUserEmail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: status.systemImageName)
                        .font(.system(size: 10))
                        .foregroundStyle(statusColor(status))
                    Text(status.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button {
                viewModel.testConnectionForSelectedProfile()
            } label: {
                Label("Test Connection", systemImage: "bolt.horizontal.circle")
            }
            .disabled(profile.accessMethod == .https)
            .help(profile.accessMethod == .https ? "HTTPS access uses Git credentials" : "Test SSH connection")
        }
    }

    private func statusColor(_ status: ProfileGitBindingStatus) -> Color {
        switch status.displayColorName {
        case "green":
            return .green
        case "orange":
            return .orange
        default:
            return .red
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
                Text("Access")
                    .foregroundStyle(.secondary)
                Picker("Access", selection: Binding(
                    get: { viewModel.selectedProfile?.accessMethod ?? .ssh },
                    set: { viewModel.updateSelectedProfileAccessMethod($0) }
                )) {
                    Text("SSH").tag(GitAccessMethod.ssh)
                    Text("HTTPS").tag(GitAccessMethod.https)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            if viewModel.selectedProfile?.accessMethod != .https {
                GridRow {
                    Text("SSH key")
                        .foregroundStyle(.secondary)
                    TextField("SSH key", text: Binding(
                        get: { viewModel.selectedProfile?.sshKeyPath ?? "" },
                        set: { viewModel.updateSelectedProfileSSHKeyPath($0) }
                    ))
                }
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
                Text("Credentials")
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
