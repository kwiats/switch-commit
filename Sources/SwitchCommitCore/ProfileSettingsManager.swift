import Foundation

public final class ProfileSettingsManager {
    public private(set) var profiles: [GitProfile]
    public private(set) var rules: [FolderRule]
    public private(set) var profileConnectionStates: [String: PersistedProfileConnectionState]
    public private(set) var activeProfileId: String?
    public private(set) var selectedProfileId: String?
    public private(set) var statusMessage: String?

    private let profileStore: ProfileStore
    private let keychainStore: KeychainStoring
    private let gitConfigInstaller: GitConfigInstalling?
    private let homeDirectory: URL

    public init(
        profileStore: ProfileStore,
        keychainStore: KeychainStoring,
        seedProfiles: [GitProfile],
        gitConfigInstaller: GitConfigInstalling? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws {
        self.profileStore = profileStore
        self.keychainStore = keychainStore
        self.gitConfigInstaller = gitConfigInstaller
        self.homeDirectory = homeDirectory.standardizedFileURL

        let loaded = try profileStore.load()
        if loaded.profiles.isEmpty {
            self.profiles = seedProfiles
            self.rules = []
            self.profileConnectionStates = [:]
        } else {
            self.profiles = loaded.profiles
            self.rules = loaded.rules
            self.profileConnectionStates = loaded.profileConnectionStates
        }

        self.activeProfileId = Self.initialProfileId(from: profiles)
        self.selectedProfileId = activeProfileId

        if loaded.profiles.isEmpty, !seedProfiles.isEmpty {
            try persist()
        }
    }

    /// Rewrites managed Git config from the current in-memory profiles and rules.
    /// Call on app/CLI startup after updates so generator changes (for example `url.insteadOf`)
    /// are applied without a manual profile switch.
    public func reapplyManagedGitConfig() throws {
        try applyGitConfig()
    }

    public var activeProfile: GitProfile? {
        profiles.first { $0.id == activeProfileId }
    }

    public var selectedProfile: GitProfile? {
        profiles.first { $0.id == selectedProfileId }
    }

    public func rules(forProfileId profileId: String) -> [FolderRule] {
        rules
            .filter { $0.profileId == profileId }
            .sorted {
                FolderRuleResolver.normalize($0.path, homeDirectory: homeDirectory)
                    < FolderRuleResolver.normalize($1.path, homeDirectory: homeDirectory)
            }
    }

    /// Reloads profiles, folder rules, and connection state from disk.
    /// Does not re-seed empty stores; callers keep prior selection when IDs still exist.
    /// If the store file is missing while in-memory profiles exist, throws instead of wiping memory.
    public func reloadFromStore() throws {
        let storeFileExists = FileManager.default.fileExists(atPath: profileStore.fileURL.path)
        let loaded = try profileStore.load()
        if !storeFileExists && !profiles.isEmpty {
            throw SwitchCommitError.profileStoreUnavailable
        }

        profiles = loaded.profiles
        rules = loaded.rules
        profileConnectionStates = loaded.profileConnectionStates

        if let activeProfileId, profiles.contains(where: { $0.id == activeProfileId }) == false {
            self.activeProfileId = Self.initialProfileId(from: profiles)
        } else if activeProfileId == nil {
            activeProfileId = Self.initialProfileId(from: profiles)
        }

        if let selectedProfileId, profiles.contains(where: { $0.id == selectedProfileId }) == false {
            self.selectedProfileId = activeProfileId
        } else if selectedProfileId == nil {
            selectedProfileId = activeProfileId
        }
    }

    @discardableResult
    public func addFolderRule(
        path: String,
        profileId: String,
        matchMode: FolderRuleMatchMode = .folderTree,
        moveIfOwned: Bool = false
    ) throws -> FolderRule {
        try reloadFromStore()
        try SecurityValidation.requireSafeIdentifier(profileId)
        guard profiles.contains(where: { $0.id == profileId }) else {
            throw FolderRuleMutationError.profileNotFound(profileId: profileId)
        }
        let normalizedPath = FolderRuleResolver.normalize(
            path,
            homeDirectory: homeDirectory
        )

        if let index = rules.firstIndex(where: {
            FolderRuleResolver.normalize(
                $0.path,
                homeDirectory: homeDirectory
            ) == normalizedPath
        }) {
            if rules[index].profileId != profileId && !moveIfOwned {
                throw FolderRuleMutationError.ownedByOtherProfile(profileId: rules[index].profileId)
            }
            rules[index].path = normalizedPath
            rules[index].profileId = profileId
            rules[index].matchMode = matchMode
            try persist()
            try applyGitConfig()
            return rules[index]
        }

        let rule = try FolderRule(
            id: uniqueRuleId(base: "rule-\(rules.count + 1)"),
            path: normalizedPath,
            profileId: profileId,
            matchMode: matchMode,
            enabled: true
        )
        rules.append(rule)
        try persist()
        try applyGitConfig()
        return rule
    }

    /// UI-facing overload that maps mutation errors to `FolderRuleError`.
    public func addFolderRule(
        path: String,
        profileId: String,
        matchMode: FolderRuleMatchMode,
        forceMove: Bool
    ) throws {
        do {
            _ = try addFolderRule(
                path: path,
                profileId: profileId,
                matchMode: matchMode,
                moveIfOwned: forceMove
            )
        } catch FolderRuleMutationError.profileNotFound {
            throw FolderRuleError.unknownProfile
        } catch FolderRuleMutationError.ownedByOtherProfile(let profileId) {
            throw FolderRuleError.pathOwnedByOtherProfile(profileId: profileId)
        }
    }

    public func removeFolderRule(id: String) throws {
        try reloadFromStore()
        guard rules.contains(where: { $0.id == id }) else {
            throw FolderRuleError.ruleNotFound
        }
        rules.removeAll { $0.id == id }
        try persist()
        try applyGitConfig()
    }

    public func removeFolderRule(path: String) throws {
        try reloadFromStore()
        let normalizedPath = FolderRuleResolver.normalize(
            path,
            homeDirectory: homeDirectory
        )
        guard let index = rules.firstIndex(where: {
            FolderRuleResolver.normalize(
                $0.path,
                homeDirectory: homeDirectory
            ) == normalizedPath
        }) else {
            return
        }
        rules.remove(at: index)
        try persist()
        try applyGitConfig()
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
        try reloadFromStore()
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
        try reloadFromStore()
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

    public func addProfile(_ profile: GitProfile) throws {
        try reloadFromStore()
        var updatedProfiles = profiles
        var addedProfile = profile
        let updatedActiveProfileId = activeProfileId ?? addedProfile.id
        addedProfile.isDefault = addedProfile.id == updatedActiveProfileId
        updatedProfiles.append(addedProfile)
        for index in updatedProfiles.indices {
            updatedProfiles[index].isDefault = updatedProfiles[index].id == updatedActiveProfileId
        }

        try profileStore.save(ProfileStoreData(
            profiles: updatedProfiles,
            rules: rules,
            profileConnectionStates: profileConnectionStates
        ))
        profiles = updatedProfiles
        selectedProfileId = addedProfile.id
        activeProfileId = updatedActiveProfileId
        try applyGitConfig()
    }

    public func updateProfile(_ profile: GitProfile) throws {
        try reloadFromStore()
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            return
        }

        var updatedProfiles = profiles
        var updatedProfile = profile
        updatedProfile.isDefault = updatedProfile.id == activeProfileId
        updatedProfiles[index] = updatedProfile
        try profileStore.save(ProfileStoreData(
            profiles: updatedProfiles,
            rules: rules,
            profileConnectionStates: profileConnectionStates
        ))
        profiles = updatedProfiles
        try applyGitConfig()
    }

    public func deleteProfile(id: String) throws {
        try reloadFromStore()
        guard profiles.contains(where: { $0.id == id }) else {
            return
        }

        profiles.removeAll { $0.id == id }
        rules.removeAll { $0.profileId == id }
        profileConnectionStates.removeValue(forKey: id)

        if profiles.isEmpty {
            selectedProfileId = nil
            activeProfileId = nil
        } else {
            let nextId = profiles.first?.id
            selectedProfileId = nextId
            if activeProfileId == id || activeProfileId == nil {
                activeProfileId = nextId
            }
        }

        normalizeDefaultFlags()
        try persist()
        try applyGitConfig()
    }

    public func importDetectedAccount(_ account: DetectedGitAccount) throws {
        try reloadFromStore()
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

        try profileStore.save(ProfileStoreData(
            profiles: updatedProfiles,
            rules: rules,
            profileConnectionStates: profileConnectionStates
        ))

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
        try deleteProfile(id: selectedProfileId)
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
        let profileId = selectedProfileId
        try updateSelectedProfile { profile in
            profile.sshKeyPath = sshKeyPath
        }
        if let profileId {
            try clearConnectionState(forProfileId: profileId)
        }
    }

    public func updateSelectedProfileAccessMethod(_ accessMethod: GitAccessMethod) throws {
        try reloadFromStore()
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
        try profileStore.save(ProfileStoreData(
            profiles: draftProfiles,
            rules: rules,
            profileConnectionStates: profileConnectionStates
        ))
        do {
            try applyGitConfig(
                profiles: draftProfiles,
                activeProfile: draftProfiles.first { $0.id == activeProfileId }
            )
        } catch {
            try? profileStore.save(ProfileStoreData(
                profiles: originalProfiles,
                rules: rules,
                profileConnectionStates: profileConnectionStates
            ))
            throw error
        }
        profiles = draftProfiles
        try clearConnectionState(forProfileId: draft.id)
    }

    public func updateSelectedProfileHostsText(_ hostsText: String) throws {
        let profileId = selectedProfileId
        let hosts = hostsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        try updateSelectedProfile { profile in
            profile.hosts = hosts
        }
        if let profileId {
            try clearConnectionState(forProfileId: profileId)
        }
    }

    public func resetAccessForSelectedProfile() throws {
        try reloadFromStore()
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

    public func saveConnectionState(_ state: PersistedProfileConnectionState, forProfileId profileId: String) throws {
        try reloadFromStore()
        guard profiles.contains(where: { $0.id == profileId }) else {
            return
        }
        profileConnectionStates[profileId] = state
        try persist()
    }

    public func clearConnectionState(forProfileId profileId: String) throws {
        try reloadFromStore()
        guard profileConnectionStates.removeValue(forKey: profileId) != nil else {
            return
        }
        try persist()
    }

    private var selectedProfileIndex: Array<GitProfile>.Index? {
        guard let selectedProfileId else {
            return nil
        }
        return profiles.firstIndex { $0.id == selectedProfileId }
    }

    private func updateSelectedProfile(_ mutate: (inout GitProfile) -> Void) throws {
        try reloadFromStore()
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
        try profileStore.save(ProfileStoreData(
            profiles: profiles,
            rules: rules,
            profileConnectionStates: profileConnectionStates
        ))
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

    private func uniqueRuleId(base: String) -> String {
        var candidate = base
        var suffix = 2
        let ids = Set(rules.map(\.id))
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
