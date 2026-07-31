import Foundation

public enum CLIExitCode: Int32 {
    case success = 0
    case usage = 1
    case failure = 2
}

public struct CLIOutput: Sendable {
    public struct Style: Sendable {
        public var colorEnabled: Bool

        public init(colorEnabled: Bool) {
            self.colorEnabled = colorEnabled
        }

        public static func detect(
            noColorFlag: Bool,
            isTTY: Bool,
            env: [String: String] = ProcessInfo.processInfo.environment
        ) -> Style {
            if noColorFlag || env["NO_COLOR"] != nil || !isTTY {
                return Style(colorEnabled: false)
            }
            return Style(colorEnabled: true)
        }
    }

    private enum ANSI {
        static let reset = "\u{001B}[0m"
        static let bold = "\u{001B}[1m"
        static let dim = "\u{001B}[2m"
        static let green = "\u{001B}[32m"
        static let cyan = "\u{001B}[36m"
    }

    private struct JSONListResponse: Encodable {
        let ok = true
        let profiles: [GitProfile]
        let activeProfileId: String?
    }

    private struct JSONShowResponse: Encodable {
        let ok = true
        let profile: GitProfile
    }

    private struct JSONRulesResponse: Encodable {
        let ok = true
        let rules: [FolderRule]
    }

    private struct JSONStatusResponse: Encodable {
        let ok = true
        let status: StatusPayload
    }

    private struct JSONDoctorResponse: Encodable {
        let ok = true
        let values: [String: String]
        let warnings: [String]
    }

    private struct JSONOKResponse: Encodable {
        let ok = true
    }

    private struct JSONErrorResponse: Encodable {
        let ok = false
        let error: String
    }

    private struct StatusPayload: Encodable {
        var activeProfileId: String?
        var contextProfileId: String?
        var contextPath: String?
        var contextSource: String
    }

    public static func humanList(
        profiles: [GitProfile],
        activeProfileId: String?,
        style: Style
    ) -> String {
        let sortedProfiles = profiles.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
        return sortedProfiles.map { profile in
            let isActive = profile.id == activeProfileId
            let marker = activeMarker(isActive: isActive, style: style)
            let id = styled(profile.id, code: ANSI.bold, style: style)
            let name = styled(profile.displayName, code: ANSI.dim, style: style)
            let email = styled(profile.gitUserEmail, code: ANSI.dim, style: style)
            return "\(marker) \(id)  \(name)  \(email)"
        }
        .joined(separator: "\n")
    }

    public static func humanStatus(snapshot: StatusSnapshot, style: Style) -> String {
        var lines: [String] = []

        if let activeProfile = snapshot.activeProfile {
            lines.append("Active: \(profileSummary(activeProfile, style: style))")
        } else {
            lines.append("Active: \(styled("none", code: ANSI.dim, style: style))")
        }

        switch snapshot.contextSource {
        case .global:
            if let contextProfile = snapshot.contextProfile {
                lines.append("Context: global → \(profileSummary(contextProfile, style: style))")
            } else {
                lines.append("Context: global → none")
            }
        case .folder:
            if let contextProfile = snapshot.contextProfile {
                let path = snapshot.contextPath ?? "unknown"
                lines.append("Context: folder → \(profileSummary(contextProfile, style: style))")
                lines.append("Path: \(path)")
            } else {
                lines.append("Context: folder → none")
            }
        case .none:
            lines.append("Context: none")
        }

        return lines.joined(separator: "\n")
    }

    public static func humanShow(profile: GitProfile, style: Style) -> String {
        [
            "Profile: \(styled(profile.id, code: ANSI.bold, style: style))",
            "Display name: \(profile.displayName)",
            "Git user: \(profile.gitUserName) <\(profile.gitUserEmail)>",
            "Access: \(profile.accessMethod.rawValue)",
            "SSH key: \(profile.sshKeyPath.isEmpty ? "—" : profile.sshKeyPath)",
            "Hosts: \(profile.hosts.joined(separator: ", "))",
            credentialRefLine(for: profile),
            "Default: \(profile.isDefault ? "yes" : "no")"
        ]
        .joined(separator: "\n")
    }

    public static func humanDoctor(report: DiagnosticsReport, style: Style) -> String {
        var lines = report.values
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { "\($0.key): \($0.value)" }
        if report.warnings.isEmpty {
            lines.append(styled("Warnings: none", code: ANSI.dim, style: style))
        } else {
            lines.append("Warnings:")
            lines.append(contentsOf: report.warnings.sorted().map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    public static func humanRules(
        rules: [FolderRule],
        profiles: [GitProfile],
        style: Style
    ) -> String {
        let sortedRules = rules.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
        if sortedRules.isEmpty {
            return styled("No folder rules.", code: ANSI.dim, style: style)
        }

        let profileNames = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.displayName) })
        return sortedRules.map { rule in
            let profileLabel = profileNames[rule.profileId] ?? rule.profileId
            let mode = rule.matchMode == .folderTree ? "folder-tree" : "single-repo"
            let enabled = rule.enabled ? "enabled" : "disabled"
            return "\(rule.path)  →  \(profileLabel)  (\(mode), \(enabled))"
        }
        .joined(separator: "\n")
    }

    public static func jsonList(profiles: [GitProfile], activeProfileId: String?) -> String {
        encode(JSONListResponse(profiles: sortedProfiles(profiles), activeProfileId: activeProfileId))
    }

    public static func jsonShow(profile: GitProfile) -> String {
        encode(JSONShowResponse(profile: profile))
    }

    public static func jsonRules(rules: [FolderRule]) -> String {
        encode(JSONRulesResponse(rules: sortedRules(rules)))
    }

    public static func jsonStatus(snapshot: StatusSnapshot) -> String {
        let payload = StatusPayload(
            activeProfileId: snapshot.activeProfile?.id,
            contextProfileId: snapshot.contextProfile?.id,
            contextPath: snapshot.contextPath,
            contextSource: snapshot.contextSource.rawValue
        )
        return encode(JSONStatusResponse(status: payload))
    }

    public static func jsonDoctor(report: DiagnosticsReport) -> String {
        encode(JSONDoctorResponse(values: report.values, warnings: report.warnings.sorted()))
    }

    public static func jsonError(_ message: String) -> String {
        encode(JSONErrorResponse(error: message))
    }

    public static func jsonOK() -> String {
        encode(JSONOKResponse())
    }

    private static func sortedProfiles(_ profiles: [GitProfile]) -> [GitProfile] {
        profiles.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    private static func sortedRules(_ rules: [FolderRule]) -> [FolderRule] {
        rules.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"ok\":false,\"error\":\"failed to encode JSON\"}"
        }
        return json
    }

    private static func activeMarker(isActive: Bool, style: Style) -> String {
        let marker = isActive ? "●" : " "
        guard isActive else { return marker }
        return styled(marker, code: ANSI.green, style: style)
    }

    private static func profileSummary(_ profile: GitProfile, style: Style) -> String {
        let id = styled(profile.id, code: ANSI.bold, style: style)
        return "\(id) (\(profile.displayName)) <\(profile.gitUserEmail)>"
    }

    private static func credentialRefLine(for profile: GitProfile) -> String {
        if let ref = profile.httpsCredentialRef {
            return "HTTPS credential ref: \(ref)"
        }
        return "HTTPS credential ref: —"
    }

    private static func styled(_ text: String, code: String, style: Style) -> String {
        guard style.colorEnabled else { return text }
        return "\(code)\(text)\(ANSI.reset)"
    }
}
