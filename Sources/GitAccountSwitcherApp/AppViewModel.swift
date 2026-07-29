import Foundation
import GitAccountSwitcherCore

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var profiles: [GitProfile]
    @Published private(set) var activeProfileId: String?
    @Published var diagnosticsText: String

    init(
        profiles: [GitProfile] = AppViewModel.previewProfiles(),
        activeProfileId: String? = nil,
        diagnosticsText: String = "Diagnostics have not run."
    ) {
        self.profiles = profiles
        self.activeProfileId = activeProfileId ?? profiles.first(where: \.isDefault)?.id ?? profiles.first?.id
        self.diagnosticsText = diagnosticsText
    }

    var activeProfile: GitProfile? {
        profiles.first { $0.id == activeProfileId }
    }

    func switchGlobalProfile(to profile: GitProfile) {
        activeProfileId = profile.id
    }

    func runLocalDiagnostics() {
        diagnosticsText = "Local diagnostics are available in the core service. No network checks run automatically."
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
