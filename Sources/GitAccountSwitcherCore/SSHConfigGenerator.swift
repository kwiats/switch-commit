import Foundation

public struct SSHConfigGenerator: Sendable {
    public init() {}

    public func managedConfig(for profiles: [GitProfile]) -> String {
        profiles
            .filter { $0.accessMethod == .ssh }
            .flatMap { profile in
                profile.hosts.map { host in
                    """
                    # Profile: \(profile.displayName)
                    Host \(host)
                        IdentityFile \(profile.sshKeyPath)
                        IdentitiesOnly yes

                    """
                }
            }
            .joined()
    }
}
