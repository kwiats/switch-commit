import Combine
import Foundation
import SwitchCommitCore

public enum AppPresentationRequest: Equatable, Sendable {
    case settings
}

public struct AppBundleInfo: Equatable, Sendable {
    public let shortVersion: String?
    public let buildVersion: String?

    public init(shortVersion: String?, buildVersion: String?) {
        self.shortVersion = shortVersion
        self.buildVersion = buildVersion
    }

    public static func mainBundle() -> AppBundleInfo {
        let info = Bundle.main.infoDictionary
        return AppBundleInfo(
            shortVersion: info?["CFBundleShortVersionString"] as? String,
            buildVersion: info?["CFBundleVersion"] as? String
        )
    }
}

public struct AppUpdatePresentation: Equatable, Sendable {
    public let productName: String
    public let installedVersion: String
    public let canCheckForUpdates: Bool
    public let privacyNote: String
}

@MainActor
public protocol AppUpdateChecking: AnyObject {
    var canCheckForUpdates: Bool { get }
    func checkForUpdates()
}

@MainActor
public final class DisabledAppUpdateChecker: AppUpdateChecking {
    public init() {}

    public var canCheckForUpdates: Bool {
        false
    }

    public func checkForUpdates() {}
}

public enum LaunchAtLoginStatus: Equatable, Sendable {
    case enabled
    case disabled
    case unavailable(message: String)

    public var isEnabled: Bool {
        switch self {
        case .enabled:
            return true
        case .disabled, .unavailable:
            return false
        }
    }

    public var displayMessage: String {
        switch self {
        case .enabled:
            return "Launch at login is enabled."
        case .disabled:
            return "Launch at login is disabled."
        case .unavailable(let message):
            return message
        }
    }
}

public protocol LaunchAtLoginManaging: Sendable {
    var status: LaunchAtLoginStatus { get }
    func enable() throws
    func disable() throws
}

public protocol CLIInstalling: Sendable {
    var statusMessage: String { get }
    func installOrRepair() throws
}

public struct UnavailableCLIInstaller: CLIInstalling {
    public init() {}

    public var statusMessage: String {
        "CLI installation is unavailable in this runtime."
    }

    public func installOrRepair() throws {}
}

public struct UnavailableLaunchAtLoginManager: LaunchAtLoginManaging {
    public init() {}

    public var status: LaunchAtLoginStatus {
        .unavailable(message: "Launch at login is unavailable in this runtime.")
    }

    public func enable() throws {}
    public func disable() throws {}
}

private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
}

private actor GitHubDiscoveryWorker {
    // The actor serializes use of the discovery service's non-Sendable command runner.
    private let service: UncheckedSendable<GitHubLocalDiscoveryService>

    init(service: UncheckedSendable<GitHubLocalDiscoveryService>) {
        self.service = service
    }

    func detect(existingProfiles: [GitProfile]) -> [DetectedGitAccount] {
        service.value.detect(existingProfiles: existingProfiles)
    }

    func detect(in folderURL: URL, existingProfiles: [GitProfile]) -> [DetectedGitAccount] {
        service.value.detect(in: folderURL, existingProfiles: existingProfiles)
    }
}

private actor HostConnectionTestWorker {
    private let service: UncheckedSendable<DiagnosticsService>

    init(service: UncheckedSendable<DiagnosticsService>) {
        self.service = service
    }

    func test(hosts: [String], identityFile: String?) -> [HostConnectionTestResult] {
        hosts.map { service.value.testSSHConnection(host: $0, identityFile: identityFile) }
    }
}

public enum ProfileGitBindingStatus: Equatable, Sendable {
    case notConnected(message: String)
    case needsAttention(message: String)
    case connected(message: String)

    public var systemImageName: String {
        "circle.fill"
    }

    public var displayColorName: String {
        switch self {
        case .notConnected:
            return "red"
        case .needsAttention:
            return "orange"
        case .connected:
            return "green"
        }
    }

    public var message: String {
        switch self {
        case .notConnected(let message), .needsAttention(let message), .connected(let message):
            return message
        }
    }
}

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public private(set) var profiles: [GitProfile]
    @Published public private(set) var activeProfileId: String?
    @Published public private(set) var selectedProfileId: String?
    @Published public private(set) var folderAssignmentsForSelectedProfile: [FolderAssignmentRow]
    @Published public private(set) var pendingFolderMatchMode: FolderRuleMatchMode
    @Published public private(set) var contextPresentation: FolderContextPresentation
    @Published public var isShowingFolderRuleMoveConfirmation: Bool
    @Published public private(set) var pendingFolderRulePath: String?
    @Published public var diagnosticsText: String
    @Published public var settingsMessage: String?
    @Published public private(set) var presentationRequest: AppPresentationRequest?
    @Published public private(set) var detectedAccounts: [DetectedGitAccount]
    @Published public private(set) var menuContentRevision: Int
    @Published public private(set) var isLaunchAtLoginEnabled: Bool
    @Published public private(set) var launchAtLoginStatusText: String
    @Published public private(set) var cliInstallStatusText: String
    @Published public private(set) var isCLIInstalled: Bool
    @Published public private(set) var availableSSHKeyPaths: [String]

    private let profileSettingsManager: ProfileSettingsManager
    private let githubDiscoveryWorker: GitHubDiscoveryWorker
    private let hostConnectionTestWorker: HostConnectionTestWorker
    private let updateChecker: AppUpdateChecking
    private let bundleInfo: AppBundleInfo
    private let launchAtLoginManager: LaunchAtLoginManaging
    private let cliInstaller: CLIInstalling
    private let sshKeyDiscovery: SSHKeyDiscovery
    private var connectionTestResultsByProfileId: [String: [HostConnectionTestResult]]
    private var frontmostPath: String?
    private var frontmostUnavailableReason: String?

    public init(
        profiles: [GitProfile]? = nil,
        activeProfileId: String? = nil,
        diagnosticsText: String = "Diagnostics have not run.",
        presentationRequest: AppPresentationRequest? = nil,
        profileStore: ProfileStore? = nil,
        keychainStore: KeychainStoring = SystemKeychainStore(),
        gitConfigInstaller: GitConfigInstalling? = nil,
        githubDiscoveryService: GitHubLocalDiscoveryService? = nil,
        diagnosticsService: DiagnosticsService = DiagnosticsService(),
        updateChecker: AppUpdateChecking = DisabledAppUpdateChecker(),
        bundleInfo: AppBundleInfo = .mainBundle(),
        launchAtLoginManager: LaunchAtLoginManaging = UnavailableLaunchAtLoginManager(),
        cliInstaller: CLIInstalling = UnavailableCLIInstaller(),
        sshKeyDiscovery: SSHKeyDiscovery = SSHKeyDiscovery()
    ) {
        let seedProfiles = profiles ?? AppViewModel.previewProfiles()
        let resolvedProfileStore = profileStore ?? ProfileStore(fileURL: profiles == nil ? AppViewModel.defaultProfilesURL() : AppViewModel.temporaryProfilesURL())
        let resolvedGitConfigInstaller = gitConfigInstaller ?? (profiles == nil ? ManagedGitConfigInstaller() : nil)
        let manager: ProfileSettingsManager
        var startupMessage: String?

        do {
            manager = try ProfileSettingsManager(
                profileStore: resolvedProfileStore,
                keychainStore: keychainStore,
                seedProfiles: seedProfiles,
                gitConfigInstaller: resolvedGitConfigInstaller
            )
        } catch {
            startupMessage = "Could not load saved profiles: \(error.localizedDescription)"
            manager = try! ProfileSettingsManager(
                profileStore: ProfileStore(fileURL: AppViewModel.temporaryProfilesURL()),
                keychainStore: InMemoryKeychainStore(),
                seedProfiles: seedProfiles,
                gitConfigInstaller: nil
            )
        }

        if let activeProfileId, let profile = manager.profiles.first(where: { $0.id == activeProfileId }) {
            try? manager.switchGlobalProfile(to: profile)
        } else {
            try? manager.reapplyManagedGitConfig()
        }

        self.profileSettingsManager = manager
        self.profiles = manager.profiles
        self.activeProfileId = manager.activeProfileId
        self.selectedProfileId = manager.selectedProfileId
        self.folderAssignmentsForSelectedProfile = Self.folderAssignmentRows(
            from: manager.rules(forProfileId: manager.selectedProfileId ?? "")
        )
        self.pendingFolderMatchMode = .folderTree
        self.contextPresentation = Self.globalContextPresentation(
            profiles: manager.profiles,
            activeProfileId: manager.activeProfileId
        )
        self.isShowingFolderRuleMoveConfirmation = false
        self.pendingFolderRulePath = nil
        self.diagnosticsText = diagnosticsText
        self.settingsMessage = startupMessage
        self.presentationRequest = presentationRequest
        self.githubDiscoveryWorker = GitHubDiscoveryWorker(
            service: UncheckedSendable(value: githubDiscoveryService ?? GitHubLocalDiscoveryService())
        )
        self.hostConnectionTestWorker = HostConnectionTestWorker(
            service: UncheckedSendable(value: diagnosticsService)
        )
        self.updateChecker = updateChecker
        self.bundleInfo = bundleInfo
        self.launchAtLoginManager = launchAtLoginManager
        self.cliInstaller = cliInstaller
        self.sshKeyDiscovery = sshKeyDiscovery
        self.connectionTestResultsByProfileId = Self.runtimeConnectionResults(
            from: manager.profileConnectionStates
        )
        self.detectedAccounts = []
        self.menuContentRevision = 0
        self.isLaunchAtLoginEnabled = launchAtLoginManager.status.isEnabled
        self.launchAtLoginStatusText = launchAtLoginManager.status.displayMessage
        self.cliInstallStatusText = cliInstaller.statusMessage
        self.isCLIInstalled = Self.isInstalledCLIStatus(cliInstaller.statusMessage)
        self.availableSSHKeyPaths = sshKeyDiscovery.discoverKeyPaths()
    }

    public var activeProfile: GitProfile? {
        profileSettingsManager.activeProfile
    }

    public var selectedProfile: GitProfile? {
        profileSettingsManager.selectedProfile
    }

    public var updatePresentation: AppUpdatePresentation {
        AppUpdatePresentation(
            productName: "Switch Commit",
            installedVersion: formattedInstalledVersion,
            canCheckForUpdates: updateChecker.canCheckForUpdates,
            privacyNote: "Checks the public Switch Commit release channel only after you click."
        )
    }

    public var hostsTextForSelectedProfile: String {
        guard let selectedProfile else {
            return ""
        }
        return profileSettingsManager.hostsText(for: selectedProfile)
    }

    public func switchGlobalProfile(to profile: GitProfile) {
        var switchedProfileId: String?
        performSettingsUpdate {
            try profileSettingsManager.switchGlobalProfile(to: profile)
            switchedProfileId = profile.id
        }
        if let switchedProfileId,
           let switchedProfile = profiles.first(where: { $0.id == switchedProfileId }) {
            testConnection(for: switchedProfile, source: .automatic)
        }
    }

    public func runLocalDiagnostics() {
        diagnosticsText = "Local diagnostics are available in the core service. No network checks run automatically."
        presentationRequest = .settings
    }

    public func checkForUpdates() {
        guard updateChecker.canCheckForUpdates else {
            settingsMessage = "Updates are not available in this build."
            return
        }
        settingsMessage = "Checking Switch Commit updates..."
        updateChecker.checkForUpdates()
    }

    public func requestSettingsPresentation() {
        presentationRequest = .settings
    }

    public func clearPresentationRequest() {
        presentationRequest = nil
    }

    public func gitBindingStatus(for profile: GitProfile) -> ProfileGitBindingStatus {
        connectionStatus(for: profile)
    }

    public func connectionStatus(for profile: GitProfile) -> ProfileGitBindingStatus {
        let hosts = normalizedHosts(for: profile)
        guard !hosts.isEmpty else {
            return .needsAttention(message: "No host configured.")
        }
        guard profile.accessMethod == .ssh else {
            return .connected(message: "Uses HTTPS credentials.")
        }
        guard !profile.sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .needsAttention(message: "No SSH key configured.")
        }
        guard let results = connectionTestResultsByProfileId[profile.id], !results.isEmpty else {
            return .notConnected(message: "Connection not tested.")
        }
        if results.allSatisfy({ $0.status == .connected }) {
            let hostText = results.map(\.host).joined(separator: ", ")
            return .connected(message: "Connected to \(hostText).")
        }
        let failedResults = results.filter { $0.status == .failed }
        let failedHosts = failedResults.map(\.host).joined(separator: ", ")
        let firstMessage = failedResults.first?.message ?? "Connection test failed."
        return .needsAttention(message: "\(failedHosts): \(firstMessage)")
    }

    public func testConnectionForSelectedProfile() {
        guard let profile = selectedProfile else {
            settingsMessage = "Select an account before testing connection."
            return
        }
        guard profile.accessMethod == .ssh else {
            settingsMessage = "HTTPS access uses Git credentials."
            connectionTestResultsByProfileId[profile.id] = []
            menuContentRevision += 1
            return
        }
        let hosts = normalizedHosts(for: profile)
        guard !hosts.isEmpty else {
            connectionTestResultsByProfileId[profile.id] = [
                HostConnectionTestResult(host: "Host", status: .failed, message: "No host configured.")
            ]
            settingsMessage = "No host configured for \(profile.displayName)."
            menuContentRevision += 1
            return
        }
        settingsMessage = "Testing connection for \(profile.displayName)..."
        testConnection(for: profile, source: .manual)
    }

    public func providerSystemImageName(for profile: GitProfile) -> String {
        let hosts = Set(profile.hosts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        if hosts.contains("github.com") {
            return "person.crop.circle.badge.checkmark"
        }
        return "terminal"
    }

    public func selectProfile(id: String?) {
        profileSettingsManager.selectProfile(id: id)
        refreshFromProfileSettings()
    }

    public func setPendingFolderMatchMode(_ matchMode: FolderRuleMatchMode) {
        pendingFolderMatchMode = matchMode
    }

    public func addFolderRuleForSelectedProfile(path: String, forceMove: Bool) {
        guard let selectedProfileId else {
            settingsMessage = "Select an account before adding a folder."
            return
        }

        do {
            try profileSettingsManager.addFolderRule(
                path: path,
                profileId: selectedProfileId,
                matchMode: pendingFolderMatchMode,
                forceMove: forceMove
            )
            settingsMessage = profileSettingsManager.statusMessage
            pendingFolderRulePath = nil
            isShowingFolderRuleMoveConfirmation = false
            refreshFromProfileSettings()
            menuContentRevision += 1
        } catch FolderRuleError.pathOwnedByOtherProfile {
            pendingFolderRulePath = path
            isShowingFolderRuleMoveConfirmation = true
        } catch {
            settingsMessage = "Could not save settings: \(error.localizedDescription)"
        }
    }

    public func removeFolderRule(id: String) {
        performSettingsUpdate {
            try profileSettingsManager.removeFolderRule(id: id)
        }
    }

    public func confirmPendingFolderRuleMove() {
        guard let path = pendingFolderRulePath else {
            isShowingFolderRuleMoveConfirmation = false
            return
        }
        addFolderRuleForSelectedProfile(path: path, forceMove: true)
    }

    public func cancelPendingFolderRuleMove() {
        pendingFolderRulePath = nil
        isShowingFolderRuleMoveConfirmation = false
    }

    public func applyFrontmostPath(_ path: String, source _: FrontmostPathSource) {
        applyFrontmostState(path: path, unavailableReason: nil)
    }

    public func applyFrontmostUnavailable(reason: String) {
        applyFrontmostState(path: nil, unavailableReason: reason)
    }

    public func applyFrontmostClearedToGlobal() {
        applyFrontmostState(path: nil, unavailableReason: nil)
    }

    public func addProfile() {
        performSettingsUpdate {
            try profileSettingsManager.addProfile()
        }
    }

    public func deleteSelectedProfile() {
        performSettingsUpdate {
            try profileSettingsManager.deleteSelectedProfile()
        }
    }

    public func updateSelectedProfileDisplayName(_ displayName: String) {
        performSettingsUpdate {
            try profileSettingsManager.updateSelectedProfileDisplayName(displayName)
        }
    }

    public func updateSelectedProfileGitUserName(_ gitUserName: String) {
        performSettingsUpdate {
            try profileSettingsManager.updateSelectedProfileGitUserName(gitUserName)
        }
    }

    public func updateSelectedProfileGitUserEmail(_ gitUserEmail: String) {
        performSettingsUpdate {
            try profileSettingsManager.updateSelectedProfileGitUserEmail(gitUserEmail)
        }
    }

    public func updateSelectedProfileSSHKeyPath(_ sshKeyPath: String) {
        performSettingsUpdate {
            try profileSettingsManager.updateSelectedProfileSSHKeyPath(sshKeyPath)
        }
    }

    public func refreshAvailableSSHKeyPaths() {
        availableSSHKeyPaths = sshKeyDiscovery.discoverKeyPaths()
    }

    public func updateSelectedProfileAccessMethod(_ accessMethod: GitAccessMethod) {
        let profileId = selectedProfile?.id
        performSettingsUpdate {
            try profileSettingsManager.updateSelectedProfileAccessMethod(accessMethod)
            if let profileId {
                connectionTestResultsByProfileId.removeValue(forKey: profileId)
            }
        }
    }

    public func updateSelectedProfileHostsText(_ hostsText: String) {
        performSettingsUpdate {
            try profileSettingsManager.updateSelectedProfileHostsText(hostsText)
        }
    }

    public func resetAccessForSelectedProfile() {
        performSettingsUpdate {
            try profileSettingsManager.resetAccessForSelectedProfile()
        }
    }

    public func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        do {
            if isEnabled {
                try launchAtLoginManager.enable()
            } else {
                try launchAtLoginManager.disable()
            }
            refreshLaunchAtLoginState()
        } catch {
            refreshLaunchAtLoginState()
            launchAtLoginStatusText = "Could not update launch at login: \(error.localizedDescription)"
        }
    }

    public func installCLI() {
        do {
            try cliInstaller.installOrRepair()
            refreshCLIInstallState()
        } catch {
            refreshCLIInstallState()
            cliInstallStatusText = "Could not install CLI: \(error.localizedDescription)"
        }
    }

    public func refreshDetectedAccounts() {
        let existingProfiles = profiles
        let worker = githubDiscoveryWorker
        Task { [weak self, worker, existingProfiles] in
            let accounts = await worker.detect(existingProfiles: existingProfiles)
            guard let self else {
                return
            }
            let filteredAccounts = accounts.filter { !isDuplicateDetectedAccount($0) }
            detectedAccounts = filteredAccounts
            if filteredAccounts.isEmpty {
                settingsMessage = "No local GitHub account was detected."
            } else {
                let noun = filteredAccounts.count == 1 ? "suggestion" : "suggestions"
                settingsMessage = "Detected \(filteredAccounts.count) local GitHub account \(noun)."
            }
        }
    }

    public func scanSelectedFolderForGitHubAccounts(_ folderURL: URL) {
        let existingProfiles = profiles
        let worker = githubDiscoveryWorker
        Task { [weak self, worker, folderURL, existingProfiles] in
            let accounts = await worker.detect(in: folderURL, existingProfiles: existingProfiles)
            guard let self else {
                return
            }
            let filteredAccounts = accounts.filter { !isDuplicateDetectedAccount($0) }
            detectedAccounts = filteredAccounts
            if filteredAccounts.isEmpty {
                settingsMessage = "No GitHub remotes were detected in the selected folder."
            } else {
                let noun = filteredAccounts.count == 1 ? "suggestion" : "suggestions"
                settingsMessage = "Detected \(filteredAccounts.count) GitHub account \(noun) from local data."
            }
        }
    }

    public func importDetectedAccount(id: String) {
        guard let account = detectedAccounts.first(where: { $0.id == id }) else {
            settingsMessage = "Detected account is no longer available."
            return
        }
        performSettingsUpdate {
            try profileSettingsManager.importDetectedAccount(account)
        }
        let existingProfiles = profiles
        let worker = githubDiscoveryWorker
        Task { [weak self, worker, existingProfiles] in
            let accounts = await worker.detect(existingProfiles: existingProfiles)
            guard let self else {
                return
            }
            detectedAccounts = accounts.filter { !isDuplicateDetectedAccount($0) }
        }
    }

    public func completeDetectedAccount(id: String) {
        guard let account = detectedAccounts.first(where: { $0.id == id }) else {
            settingsMessage = "Detected account is no longer available."
            return
        }
        do {
            try profileSettingsManager.addProfile()
            if let displayName = account.username ?? account.gitUserName {
                try profileSettingsManager.updateSelectedProfileDisplayName(displayName)
            }
            if let gitUserName = account.gitUserName ?? account.username {
                try profileSettingsManager.updateSelectedProfileGitUserName(gitUserName)
            }
            if let accessMethod = preferredAccessMethod(for: account) {
                try profileSettingsManager.updateSelectedProfileAccessMethod(accessMethod)
            }
            if let sshKeyPath = account.sshKeyPath {
                try profileSettingsManager.updateSelectedProfileSSHKeyPath(sshKeyPath)
            }
            if !account.hosts.isEmpty {
                try profileSettingsManager.updateSelectedProfileHostsText(account.hosts.joined(separator: ", "))
            }
            refreshFromProfileSettings()
            menuContentRevision += 1
            detectedAccounts.removeAll { $0.id == id }
            settingsMessage = "Complete the detected GitHub account before using it."
        } catch {
            settingsMessage = "Could not save settings: \(error.localizedDescription)"
            refreshFromProfileSettings()
        }
    }

    private func preferredAccessMethod(for account: DetectedGitAccount) -> GitAccessMethod? {
        if account.accessMethods.contains(.ssh), !account.accessMethods.contains(.https) {
            return .ssh
        }
        if account.accessMethods.contains(.ssh), account.sshKeyPath != nil {
            return .ssh
        }
        if account.accessMethods.contains(.https) {
            return .https
        }
        return nil
    }

    private func performSettingsUpdate(_ update: () throws -> Void) {
        do {
            try update()
            settingsMessage = profileSettingsManager.statusMessage
            refreshFromProfileSettings()
            menuContentRevision += 1
        } catch {
            settingsMessage = "Could not save settings: \(error.localizedDescription)"
        }
    }

    private func refreshFromProfileSettings() {
        profiles = profileSettingsManager.profiles
        activeProfileId = profileSettingsManager.activeProfileId
        selectedProfileId = profileSettingsManager.selectedProfileId
        folderAssignmentsForSelectedProfile = Self.folderAssignmentRows(
            from: profileSettingsManager.rules(forProfileId: selectedProfileId ?? "")
        )
        refreshContextPresentation()
    }

    private func globalFolderRuleResolution() -> FolderRuleResolution {
        FolderRuleResolution(
            kind: .global,
            rule: nil,
            profile: profileSettingsManager.activeProfile
        )
    }

    private func applyFrontmostState(path: String?, unavailableReason: String?) {
        let previousPresentation = contextPresentation
        frontmostPath = path
        frontmostUnavailableReason = unavailableReason
        refreshContextPresentation()
        if contextPresentation != previousPresentation {
            menuContentRevision += 1
        }
    }

    private func refreshContextPresentation() {
        if let frontmostUnavailableReason {
            contextPresentation = FolderContextPresentation.from(
                resolution: globalFolderRuleResolution(),
                path: nil,
                unavailableReason: frontmostUnavailableReason
            )
            return
        }
        if let frontmostPath {
            let resolution = FolderRuleResolver.resolve(
                path: frontmostPath,
                rules: profileSettingsManager.rules,
                profiles: profileSettingsManager.profiles,
                activeProfileId: profileSettingsManager.activeProfileId
            )
            contextPresentation = FolderContextPresentation.from(
                resolution: resolution,
                path: frontmostPath,
                unavailableReason: nil
            )
            return
        }
        contextPresentation = FolderContextPresentation.from(
            resolution: globalFolderRuleResolution(),
            path: nil,
            unavailableReason: nil
        )
    }

    private static func globalContextPresentation(
        profiles: [GitProfile],
        activeProfileId: String?
    ) -> FolderContextPresentation {
        let resolution = FolderRuleResolution(
            kind: .global,
            rule: nil,
            profile: profiles.first { $0.id == activeProfileId }
        )
        return FolderContextPresentation.from(
            resolution: resolution,
            path: nil,
            unavailableReason: nil
        )
    }

    private static func folderAssignmentRows(from rules: [FolderRule]) -> [FolderAssignmentRow] {
        rules.map {
            FolderAssignmentRow(id: $0.id, path: $0.path, matchMode: $0.matchMode)
        }
    }

    private func refreshLaunchAtLoginState() {
        let status = launchAtLoginManager.status
        isLaunchAtLoginEnabled = status.isEnabled
        launchAtLoginStatusText = status.displayMessage
    }

    private func refreshCLIInstallState() {
        let statusMessage = cliInstaller.statusMessage
        cliInstallStatusText = statusMessage
        isCLIInstalled = Self.isInstalledCLIStatus(statusMessage)
    }

    private static func isInstalledCLIStatus(_ statusMessage: String) -> Bool {
        statusMessage.hasPrefix("CLI is installed at ")
    }

    private func isDuplicateDetectedAccount(_ account: DetectedGitAccount) -> Bool {
        profiles.contains { profile in
            let hosts = Set(profile.hosts.map { $0.lowercased() })
            guard hosts.contains("github.com") else {
                return false
            }
            if let email = account.gitUserEmail, profile.gitUserEmail.caseInsensitiveCompare(email) == .orderedSame {
                return true
            }
            if let username = account.username, profile.displayName.caseInsensitiveCompare(username) == .orderedSame {
                return true
            }
            return false
        }
    }

    private func normalizedHosts(for profile: GitProfile) -> [String] {
        profile.hosts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private enum ConnectionTestSource {
        case manual
        case automatic
    }

    private func testConnection(for profile: GitProfile, source: ConnectionTestSource) {
        guard profile.accessMethod == .ssh,
              !profile.sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }
        let hosts = normalizedHosts(for: profile)
        guard !hosts.isEmpty else {
            return
        }
        let worker = hostConnectionTestWorker
        let identityFile = profile.sshKeyPath
        Task { [weak self, worker, profile, hosts, source, identityFile] in
            let results = await worker.test(hosts: hosts, identityFile: identityFile)
            guard let self else {
                return
            }
            guard let currentProfile = profiles.first(where: { $0.id == profile.id }),
                  currentProfile.accessMethod == profile.accessMethod,
                  currentProfile.accessMethod == .ssh
            else {
                return
            }

            connectionTestResultsByProfileId[profile.id] = results
            do {
                try profileSettingsManager.saveConnectionState(
                    Self.persistedConnectionState(profileId: profile.id, results: results),
                    forProfileId: profile.id
                )
            } catch {
                if source == .manual || selectedProfileId == profile.id || activeProfileId == profile.id {
                    settingsMessage = "Could not save connection status: \(error.localizedDescription)"
                }
                menuContentRevision += 1
                return
            }

            if source == .manual || selectedProfileId == profile.id || activeProfileId == profile.id {
                settingsMessage = connectionStatus(for: currentProfile).message
            }
            menuContentRevision += 1
        }
    }

    private static func runtimeConnectionResults(
        from states: [String: PersistedProfileConnectionState]
    ) -> [String: [HostConnectionTestResult]] {
        states.mapValues { state in
            state.results.map { result in
                HostConnectionTestResult(
                    host: result.host,
                    status: result.status == .connected ? .connected : .failed,
                    message: result.message
                )
            }
        }
    }

    private static func persistedConnectionState(
        profileId: String,
        results: [HostConnectionTestResult]
    ) -> PersistedProfileConnectionState {
        PersistedProfileConnectionState(
            profileId: profileId,
            testedAt: ISO8601DateFormatter().string(from: Date()),
            results: results.map { result in
                PersistedHostConnectionTestResult(
                    host: result.host,
                    status: result.status == .connected ? .connected : .failed,
                    message: result.message
                )
            }
        )
    }

    private var formattedInstalledVersion: String {
        let shortVersion = bundleInfo.shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let buildVersion = bundleInfo.buildVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (shortVersion?.isEmpty == false ? shortVersion : nil, buildVersion?.isEmpty == false ? buildVersion : nil) {
        case (.some(let shortVersion), .some(let buildVersion)):
            return "\(shortVersion) (\(buildVersion))"
        case (.some(let shortVersion), nil):
            return shortVersion
        case (nil, .some(let buildVersion)):
            return "Build \(buildVersion)"
        case (nil, nil):
            return "Development Build"
        }
    }

    private static func defaultProfilesURL() -> URL {
        SwitchCommitPaths.defaultProfilesURL()
    }

    private static func temporaryProfilesURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("profiles.json")
    }

    public static func previewProfiles() -> [GitProfile] {
        [
            try! GitProfile(
                id: "personal",
                displayName: "Personal",
                gitUserName: "Personal User",
                gitUserEmail: "me@example.com",
                accessMethod: .ssh,
                sshKeyPath: "~/.ssh/id_ed25519",
                hosts: ["github.com"],
                httpsCredentialRef: nil,
                isDefault: true
            )
        ]
    }
}
