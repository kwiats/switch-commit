import Combine
import Foundation
import GitAccountSwitcherCore

public enum AppPresentationRequest: Equatable, Sendable {
    case settings
}

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public private(set) var profiles: [GitProfile]
    @Published public private(set) var activeProfileId: String?
    @Published public private(set) var selectedProfileId: String?
    @Published public var diagnosticsText: String
    @Published public var settingsMessage: String?
    @Published public private(set) var presentationRequest: AppPresentationRequest?

    private let profileSettingsManager: ProfileSettingsManager

    public init(
        profiles: [GitProfile]? = nil,
        activeProfileId: String? = nil,
        diagnosticsText: String = "Diagnostics have not run.",
        presentationRequest: AppPresentationRequest? = nil,
        profileStore: ProfileStore? = nil,
        keychainStore: KeychainStoring = SystemKeychainStore()
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
