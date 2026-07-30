import Foundation

public final class ProfileSettingsManager {
    public private(set) var profiles: [GitProfile]
    public private(set) var rules: [FolderRule]
    public private(set) var activeProfileId: String?
    public private(set) var selectedProfileId: String?
    public private(set) var statusMessage: String?

    private let profileStore: ProfileStore
    private let keychainStore: KeychainStoring
    private let gitConfigInstaller: GitConfigInstalling?

    public init(
        profileStore: ProfileStore,
        keychainStore: KeychainStoring,
        seedProfiles: [GitProfile],
        gitConfigInstaller: GitConfigInstalling? = nil
    ) throws {
        self.profileStore = profileStore
        self.keychainStore = keychainStore
        self.gitConfigInstaller = gitConfigInstaller

        let loaded = try profileStore.load()
        if loaded.profiles.isEmpty {
            self.profiles = seedProfiles
            self.rules = []
        } else {
            self.profiles = loaded.profiles
            self.rules = loaded.rules
        }

        self.activeProfileId = Self.initialProfileId(from: profiles)
        self.selectedProfileId = activeProfileId

        if loaded.profiles.isEmpty, !seedProfiles.isEmpty {
            try persist()
        }
    }

    public var activeProfile: GitProfile? {
        profiles.first { $0.id == activeProfileId }
    }

    public var selectedProfile: GitProfile? {
        profiles.first { $0.id == selectedProfileId }
    }

    public func selectProfile(id: String?) {
        guard let id else {
            selectedProfileId = nil
            return
        }
        if profiles.contains(where: { $0.id == id }) {
            selectedProfileId = id
        }
    }

    public func switchGlobalProfile(to profile: GitProfile) throws {
        guard profiles.contains(where: { $0.id == profile.id }) else {
            return
        }
        activeProfileId = profile.id
        for index in profiles.indices {
            profiles[index].isDefault = profiles[index].id == profile.id
        }
        try persist()
        try applyGitConfig()
    }

    public func addProfile() throws {
        let number = profiles.count + 1
        let profile = try GitProfile(
            id: uniqueProfileId(base: "account-\(number)"),
            displayName: "New Account \(number)",
            gitUserName: "Git User \(number)",
            gitUserEmail: "user\(number)@example.com",
            accessMethod: .ssh,
            sshKeyPath: "~/.ssh/id_ed25519",
            hosts: ["github.com"],
            httpsCredentialRef: nil,
            isDefault: profiles.isEmpty
        )

        profiles.append(profile)
        selectedProfileId = profile.id
        if activeProfileId == nil {
            activeProfileId = profile.id
        }
        try persist()
        try applyGitConfig()
    }

    public func importDetectedAccount(_ account: DetectedGitAccount) throws {
        let displayName = account.username ?? account.gitUserName ?? "GitHub Account"
        let gitUserName = account.gitUserName ?? account.username ?? ""
        let gitUserEmail = account.gitUserEmail ?? ""
        let accessMethod: GitAccessMethod
        if account.accessMethods.contains(.ssh), !account.accessMethods.contains(.https) {
            accessMethod = .ssh
        } else if account.accessMethods.contains(.ssh), account.sshKeyPath != nil {
            accessMethod = .ssh
        } else if account.accessMethods.contains(.https) {
            accessMethod = .https
        } else {
            accessMethod = account.sshKeyPath == nil ? .https : .ssh
        }
        let sshKeyPath = accessMethod == .ssh ? (account.sshKeyPath ?? "~/.ssh/id_ed25519") : ""
        let hosts = account.hosts.isEmpty ? ["github.com"] : account.hosts
        let profileId = uniqueProfileId(base: account.id)

        let profile = try GitProfile(
            id: profileId,
            displayName: displayName,
            gitUserName: gitUserName,
            gitUserEmail: gitUserEmail,
            accessMethod: accessMethod,
            sshKeyPath: sshKeyPath,
            hosts: hosts,
            httpsCredentialRef: nil,
            isDefault: profiles.isEmpty
        )

        var updatedProfiles = profiles
        updatedProfiles.append(profile)
        let updatedActiveProfileId = activeProfileId ?? profile.id
        for index in updatedProfiles.indices {
            updatedProfiles[index].isDefault = updatedProfiles[index].id == updatedActiveProfileId
        }

        try profileStore.save(ProfileStoreData(profiles: updatedProfiles, rules: rules))

        profiles = updatedProfiles
        selectedProfileId = profile.id
        activeProfileId = updatedActiveProfileId
        statusMessage = "Added detected GitHub account \(profile.displayName)."
        try applyGitConfig()
    }

    public func deleteSelectedProfile() throws {
        guard let selectedProfileId else {
            return
        }

        profiles.removeAll { $0.id == selectedProfileId }
        rules.removeAll { $0.profileId == selectedProfileId }

        if profiles.isEmpty {
            self.selectedProfileId = nil
            activeProfileId = nil
        } else {
            let nextId = profiles.first?.id
            self.selectedProfileId = nextId
            if activeProfileId == selectedProfileId || activeProfileId == nil {
                activeProfileId = nextId
            }
        }

        normalizeDefaultFlags()
        try persist()
        try applyGitConfig()
    }

    public func updateSelectedProfileDisplayName(_ displayName: String) throws {
        try updateSelectedProfile { profile in
            profile.displayName = displayName
        }
    }

    public func updateSelectedProfileGitUserName(_ gitUserName: String) throws {
        try updateSelectedProfile { profile in
            profile.gitUserName = gitUserName
        }
    }

    public func updateSelectedProfileGitUserEmail(_ gitUserEmail: String) throws {
        try updateSelectedProfile { profile in
            profile.gitUserEmail = gitUserEmail
        }
    }

    public func updateSelectedProfileSSHKeyPath(_ sshKeyPath: String) throws {
        try updateSelectedProfile { profile in
            profile.sshKeyPath = sshKeyPath
        }
    }

    public func updateSelectedProfileAccessMethod(_ accessMethod: GitAccessMethod) throws {
        guard let index = selectedProfileIndex else {
            return
        }

        var draftProfiles = profiles
        var draft = draftProfiles[index]
        draft.accessMethod = accessMethod
        if accessMethod == .https {
            draft.sshKeyPath = ""
        } else if draft.sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.sshKeyPath = "~/.ssh/id_ed25519"
        }
        draftProfiles[index] = try GitProfile(
            id: draft.id,
            displayName: draft.displayName,
            gitUserName: draft.gitUserName,
            gitUserEmail: draft.gitUserEmail,
            accessMethod: draft.accessMethod,
            sshKeyPath: draft.sshKeyPath,
            hosts: draft.hosts,
            httpsCredentialRef: draft.httpsCredentialRef,
            isDefault: draft.isDefault
        )

        let originalProfiles = profiles
        try profileStore.save(ProfileStoreData(profiles: draftProfiles, rules: rules))
        do {
            try applyGitConfig(
                profiles: draftProfiles,
                activeProfile: draftProfiles.first { $0.id == activeProfileId }
            )
        } catch {
            try? profileStore.save(ProfileStoreData(profiles: originalProfiles, rules: rules))
            throw error
        }
        profiles = draftProfiles
    }

    public func updateSelectedProfileHostsText(_ hostsText: String) throws {
        let hosts = hostsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        try updateSelectedProfile { profile in
            profile.hosts = hosts
        }
    }

    public func resetAccessForSelectedProfile() throws {
        guard let index = selectedProfileIndex else {
            return
        }

        let storedReference = profiles[index].httpsCredentialRef
        let expectedIdentifier = KeychainCredentialIdentifier(profileId: profiles[index].id, purpose: "https")

        if let storedReference, storedReference == expectedIdentifier.rawValue {
            try keychainStore.delete(expectedIdentifier)
            statusMessage = "Access reset for \(profiles[index].displayName)."
        } else if let storedReference {
            try keychainStore.delete(KeychainCredentialIdentifier(rawValue: storedReference))
            statusMessage = "Access reset for \(profiles[index].displayName)."
        } else {
            statusMessage = "No local access was stored for \(profiles[index].displayName)."
        }

        profiles[index].httpsCredentialRef = nil
        try persist()
        try applyGitConfig()
    }

    public func hostsText(for profile: GitProfile) -> String {
        profile.hosts.joined(separator: ", ")
    }

    private var selectedProfileIndex: Array<GitProfile>.Index? {
        guard let selectedProfileId else {
            return nil
        }
        return profiles.firstIndex { $0.id == selectedProfileId }
    }

    private func updateSelectedProfile(_ mutate: (inout GitProfile) -> Void) throws {
        guard let index = selectedProfileIndex else {
            return
        }

        var draft = profiles[index]
        mutate(&draft)
        profiles[index] = try GitProfile(
            id: draft.id,
            displayName: draft.displayName,
            gitUserName: draft.gitUserName,
            gitUserEmail: draft.gitUserEmail,
            accessMethod: draft.accessMethod,
            sshKeyPath: draft.sshKeyPath,
            hosts: draft.hosts,
            httpsCredentialRef: draft.httpsCredentialRef,
            isDefault: draft.isDefault
        )
        try persist()
        try applyGitConfig()
    }

    private func normalizeDefaultFlags() {
        for index in profiles.indices {
            profiles[index].isDefault = profiles[index].id == activeProfileId
        }
    }

    private func persist() throws {
        try profileStore.save(ProfileStoreData(profiles: profiles, rules: rules))
    }

    private func applyGitConfig() throws {
        try applyGitConfig(profiles: profiles, activeProfile: activeProfile)
    }

    private func applyGitConfig(profiles: [GitProfile], activeProfile: GitProfile?) throws {
        try gitConfigInstaller?.apply(
            profiles: profiles,
            rules: rules,
            activeProfile: activeProfile
        )
    }

    private func uniqueProfileId(base: String) -> String {
        var candidate = base
        var suffix = 2
        let ids = Set(profiles.map(\.id))
        while ids.contains(candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private static func initialProfileId(from profiles: [GitProfile]) -> String? {
        profiles.first(where: \.isDefault)?.id ?? profiles.first?.id
    }
}
