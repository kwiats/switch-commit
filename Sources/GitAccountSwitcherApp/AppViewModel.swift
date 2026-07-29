import Foundation
import GitAccountSwitcherCore

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var profiles: [GitProfile]
    @Published private(set) var activeProfileId: String?
    @Published private(set) var selectedProfileId: String?
    @Published var diagnosticsText: String
    @Published var settingsMessage: String?

    private let profileSettingsManager: ProfileSettingsManager

    init(
        profileStore: ProfileStore = ProfileStore(fileURL: AppViewModel.defaultProfilesURL()),
        keychainStore: KeychainStoring = SystemKeychainStore(),
        diagnosticsText: String = "Diagnostics have not run."
    ) {
        let manager: ProfileSettingsManager
        var startupMessage: String?

        do {
            manager = try ProfileSettingsManager(
                profileStore: profileStore,
                keychainStore: keychainStore,
                seedProfiles: AppViewModel.previewProfiles()
            )
        } catch {
            startupMessage = "Could not load saved profiles: \(error.localizedDescription)"
            manager = try! ProfileSettingsManager(
                profileStore: ProfileStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("git-account-switcher-preview-profiles.json")),
                keychainStore: InMemoryKeychainStore(),
                seedProfiles: AppViewModel.previewProfiles()
            )
        }

        self.profileSettingsManager = manager
        self.profiles = manager.profiles
        self.activeProfileId = manager.activeProfileId
        self.selectedProfileId = manager.selectedProfileId
        self.diagnosticsText = diagnosticsText
        self.settingsMessage = startupMessage
    }

    var activeProfile: GitProfile? {
        profileSettingsManager.activeProfile
    }

    var selectedProfile: GitProfile? {
        profileSettingsManager.selectedProfile
    }

    var hostsTextForSelectedProfile: String {
        guard let selectedProfile else {
            return ""
        }
        return profileSettingsManager.hostsText(for: selectedProfile)
    }

    func switchGlobalProfile(to profile: GitProfile) {
        performSettingsUpdate {
            try profileSettingsManager.switchGlobalProfile(to: profile)
        }
    }

    func runLocalDiagnostics() {
        diagnosticsText = "Local diagnostics are available in the core service. No network checks run automatically."
    }

    func selectProfile(id: String?) {
        profileSettingsManager.selectProfile(id: id)
        refreshFromProfileSettings()
    }

    func addProfile() {
        performSettingsUpdate {
            try profileSettingsManager.addProfile()
        }
    }

    func deleteSelectedProfile() {
        performSettingsUpdate {
            try profileSettingsManager.deleteSelectedProfile()
        }
    }

    func updateSelectedProfileDisplayName(_ displayName: String) {
        performSettingsUpdate {
            try profileSettingsManager.updateSelectedProfileDisplayName(displayName)
        }
    }

    func updateSelectedProfileGitUserName(_ gitUserName: String) {
        performSettingsUpdate {
            try profileSettingsManager.updateSelectedProfileGitUserName(gitUserName)
        }
    }

    func updateSelectedProfileGitUserEmail(_ gitUserEmail: String) {
        performSettingsUpdate {
            try profileSettingsManager.updateSelectedProfileGitUserEmail(gitUserEmail)
        }
    }

    func updateSelectedProfileSSHKeyPath(_ sshKeyPath: String) {
        performSettingsUpdate {
            try profileSettingsManager.updateSelectedProfileSSHKeyPath(sshKeyPath)
        }
    }

    func updateSelectedProfileHostsText(_ hostsText: String) {
        performSettingsUpdate {
            try profileSettingsManager.updateSelectedProfileHostsText(hostsText)
        }
    }

    func resetAccessForSelectedProfile() {
        performSettingsUpdate {
            try profileSettingsManager.resetAccessForSelectedProfile()
        }
    }

    private func performSettingsUpdate(_ update: () throws -> Void) {
        do {
            try update()
            settingsMessage = profileSettingsManager.statusMessage
        } catch {
            settingsMessage = "Could not save settings: \(error.localizedDescription)"
        }
        refreshFromProfileSettings()
    }

    private func refreshFromProfileSettings() {
        profiles = profileSettingsManager.profiles
        activeProfileId = profileSettingsManager.activeProfileId
        selectedProfileId = profileSettingsManager.selectedProfileId
    }

    private static func defaultProfilesURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("git-account-switcher", isDirectory: true)
            .appendingPathComponent("profiles.json")
    }

    private static func previewProfiles() -> [GitProfile] {
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
