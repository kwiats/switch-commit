import Combine
import Foundation
import GitAccountSwitcherCore

public enum AppPresentationRequest: Equatable, Sendable {
    case settings
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

public enum ProfileGitBindingStatus: Equatable, Sendable {
    case mockLinked

    public var systemImageName: String {
        switch self {
        case .mockLinked:
            return "link.circle.fill"
        }
    }
}

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public private(set) var profiles: [GitProfile]
    @Published public private(set) var activeProfileId: String?
    @Published public private(set) var selectedProfileId: String?
    @Published public var diagnosticsText: String
    @Published public var settingsMessage: String?
    @Published public private(set) var presentationRequest: AppPresentationRequest?
    @Published public private(set) var detectedAccounts: [DetectedGitAccount]
    @Published public private(set) var menuContentRevision: Int

    private let profileSettingsManager: ProfileSettingsManager
    private let githubDiscoveryWorker: GitHubDiscoveryWorker

    public init(
        profiles: [GitProfile]? = nil,
        activeProfileId: String? = nil,
        diagnosticsText: String = "Diagnostics have not run.",
        presentationRequest: AppPresentationRequest? = nil,
        profileStore: ProfileStore? = nil,
        keychainStore: KeychainStoring = SystemKeychainStore(),
        githubDiscoveryService: GitHubLocalDiscoveryService? = nil
    ) {
        let seedProfiles = profiles ?? AppViewModel.previewProfiles()
        let resolvedProfileStore = profileStore ?? ProfileStore(fileURL: profiles == nil ? AppViewModel.defaultProfilesURL() : AppViewModel.temporaryProfilesURL())
        let manager: ProfileSettingsManager
        var startupMessage: String?

        do {
            manager = try ProfileSettingsManager(
                profileStore: resolvedProfileStore,
                keychainStore: keychainStore,
                seedProfiles: seedProfiles
            )
        } catch {
            startupMessage = "Could not load saved profiles: \(error.localizedDescription)"
            manager = try! ProfileSettingsManager(
                profileStore: ProfileStore(fileURL: AppViewModel.temporaryProfilesURL()),
                keychainStore: InMemoryKeychainStore(),
                seedProfiles: seedProfiles
            )
        }

        if let activeProfileId, let profile = manager.profiles.first(where: { $0.id == activeProfileId }) {
            try? manager.switchGlobalProfile(to: profile)
        }

        self.profileSettingsManager = manager
        self.profiles = manager.profiles
        self.activeProfileId = manager.activeProfileId
        self.selectedProfileId = manager.selectedProfileId
        self.diagnosticsText = diagnosticsText
        self.settingsMessage = startupMessage
        self.presentationRequest = presentationRequest
        self.githubDiscoveryWorker = GitHubDiscoveryWorker(
            service: UncheckedSendable(value: githubDiscoveryService ?? GitHubLocalDiscoveryService())
        )
        self.detectedAccounts = []
        self.menuContentRevision = 0
    }

    public var activeProfile: GitProfile? {
        profileSettingsManager.activeProfile
    }

    public var selectedProfile: GitProfile? {
        profileSettingsManager.selectedProfile
    }

    public var hostsTextForSelectedProfile: String {
        guard let selectedProfile else {
            return ""
        }
        return profileSettingsManager.hostsText(for: selectedProfile)
    }

    public func switchGlobalProfile(to profile: GitProfile) {
        performSettingsUpdate {
            try profileSettingsManager.switchGlobalProfile(to: profile)
        }
    }

    public func runLocalDiagnostics() {
        diagnosticsText = "Local diagnostics are available in the core service. No network checks run automatically."
        presentationRequest = .settings
    }

    public func requestSettingsPresentation() {
        presentationRequest = .settings
    }

    public func clearPresentationRequest() {
        presentationRequest = nil
    }

    public func gitBindingStatus(for profile: GitProfile) -> ProfileGitBindingStatus {
        .mockLinked
    }

    public func selectProfile(id: String?) {
        profileSettingsManager.selectProfile(id: id)
        refreshFromProfileSettings()
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

    private static func defaultProfilesURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("git-account-switcher", isDirectory: true)
            .appendingPathComponent("profiles.json")
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
                sshKeyPath: "~/.ssh/id_ed25519",
                hosts: ["github.com"],
                httpsCredentialRef: nil,
                isDefault: true
            )
        ]
    }
}
