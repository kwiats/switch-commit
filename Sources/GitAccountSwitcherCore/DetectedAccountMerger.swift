import Foundation

public struct DetectedAccountMerger: Sendable {
    public init() {}

    public func merge(signals: [DetectionSignal], existingProfiles: [GitProfile]) -> [DetectedGitAccount] {
        let githubSignals = signals.filter { $0.provider == .github }
        guard githubSignals.contains(where: { $0.source != .globalGitConfig }) else {
            return []
        }

        var candidate = DetectedGitAccount(
            id: "github-account",
            provider: .github,
            username: nil,
            gitUserName: nil,
            gitUserEmail: nil,
            sshKeyPath: nil,
            hosts: ["github.com"],
            confidence: .low,
            sources: [],
            warnings: []
        )

        for signal in githubSignals {
            candidate.username = candidate.username ?? signal.username
            candidate.gitUserName = candidate.gitUserName ?? signal.gitUserName
            candidate.gitUserEmail = candidate.gitUserEmail ?? signal.gitUserEmail
            candidate.sshKeyPath = candidate.sshKeyPath ?? signal.sshKeyPath
            candidate.hosts = unique(candidate.hosts + signal.hosts)
            candidate.sources = unique(candidate.sources + [signal.source])
            candidate.warnings = unique(candidate.warnings + signal.warnings)
            candidate.confidence = max(candidate.confidence, signal.confidence)
        }

        candidate.id = stableId(for: candidate)
        guard !isDuplicate(candidate, existingProfiles: existingProfiles) else {
            return []
        }
        return [candidate]
    }

    private func stableId(for account: DetectedGitAccount) -> String {
        if let username = account.username, let safe = safeIdentifier("github-\(username)") {
            return safe
        }
        if let email = account.gitUserEmail, let safe = safeIdentifier("github-\(email)") {
            return safe
        }
        return "github-account"
    }

    private func safeIdentifier(_ value: String) -> String? {
        let normalized = value
            .lowercased()
            .map { character -> Character in
                if character.isLetter || character.isNumber || character == "-" || character == "_" || character == "." {
                    return character
                }
                return "-"
            }
        let id = String(normalized).trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        do {
            try SecurityValidation.requireSafeIdentifier(id)
            return id
        } catch {
            return nil
        }
    }

    private func isDuplicate(_ account: DetectedGitAccount, existingProfiles: [GitProfile]) -> Bool {
        existingProfiles.contains { profile in
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

    private func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        var result: [T] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }
}
