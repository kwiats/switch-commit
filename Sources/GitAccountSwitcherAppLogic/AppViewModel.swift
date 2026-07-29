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
    @Published public var diagnosticsText: String
    @Published public private(set) var presentationRequest: AppPresentationRequest?

    public init(
        profiles: [GitProfile] = AppViewModel.previewProfiles(),
        activeProfileId: String? = nil,
        diagnosticsText: String = "Diagnostics have not run.",
        presentationRequest: AppPresentationRequest? = nil
    ) {
        self.profiles = profiles
        self.activeProfileId = activeProfileId ?? profiles.first(where: \.isDefault)?.id ?? profiles.first?.id
        self.diagnosticsText = diagnosticsText
        self.presentationRequest = presentationRequest
    }

    public var activeProfile: GitProfile? {
        profiles.first { $0.id == activeProfileId }
    }

    public func switchGlobalProfile(to profile: GitProfile) {
        activeProfileId = profile.id
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
