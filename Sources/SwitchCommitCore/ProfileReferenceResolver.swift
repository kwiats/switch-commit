import Foundation

public enum ProfileReferenceError: Error, Equatable, Sendable {
    case notFound(String)
    case ambiguous(String, candidates: [String])
}

public enum ProfileReferenceResolver: Sendable {
    public static func resolve(_ reference: String, in profiles: [GitProfile]) throws -> GitProfile {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if let byId = profiles.first(where: { $0.id == trimmed }) {
            return byId
        }
        let matches = profiles.filter { $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame }
        switch matches.count {
        case 1:
            return matches[0]
        case 0:
            throw ProfileReferenceError.notFound(trimmed)
        default:
            throw ProfileReferenceError.ambiguous(trimmed, candidates: matches.map(\.id).sorted())
        }
    }
}
