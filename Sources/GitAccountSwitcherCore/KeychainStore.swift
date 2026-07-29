import Foundation
import Security

public struct KeychainCredentialIdentifier: Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(profileId: String, purpose: String) {
        self.rawValue = "git-account-switcher.\(profileId).\(purpose)"
    }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public protocol KeychainStoring: AnyObject {
    func save(_ value: String, for identifier: KeychainCredentialIdentifier) throws
    func read(_ identifier: KeychainCredentialIdentifier) throws -> String?
    func delete(_ identifier: KeychainCredentialIdentifier) throws
}

public final class InMemoryKeychainStore: KeychainStoring {
    private var values: [KeychainCredentialIdentifier: String] = [:]

    public init() {}

    public func save(_ value: String, for identifier: KeychainCredentialIdentifier) throws {
        values[identifier] = value
    }

    public func read(_ identifier: KeychainCredentialIdentifier) throws -> String? {
        values[identifier]
    }

    public func delete(_ identifier: KeychainCredentialIdentifier) throws {
        values.removeValue(forKey: identifier)
    }
}

public final class SystemKeychainStore: KeychainStoring {
    public init() {}

    public func save(_ value: String, for identifier: KeychainCredentialIdentifier) throws {
        try delete(identifier)
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "GitAccountSwitcher",
            kSecAttrAccount as String: identifier.rawValue,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    public func read(_ identifier: KeychainCredentialIdentifier) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "GitAccountSwitcher",
            kSecAttrAccount as String: identifier.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return String(data: data, encoding: .utf8)
    }

    public func delete(_ identifier: KeychainCredentialIdentifier) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "GitAccountSwitcher",
            kSecAttrAccount as String: identifier.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
