import Foundation
import Security

public final class KeychainCredentialStore: CredentialStore {
    private let service = "io.esimplified.glance"
    private let account = "bearer"

    public init() {}

    // App↔widget token sharing relies on the shared keychain access group declared
    // in both targets' entitlements (io.esimplified.glance.shared, listed as the sole
    // group). With a single group in the entitlement, keychain services adds items to
    // it and searches it without an explicit kSecAttrAccessGroup — so none is set here.

    public func save(_ credentials: Credentials) throws {
        try clear()
        let payload = "\(credentials.host)\n\(credentials.token)"
        let data = Data(payload.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    public func load() throws -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let payload = String(data: data, encoding: .utf8) else {
            throw KeychainError.unhandled(status)
        }
        let parts = payload.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return Credentials(host: String(parts[0]), token: String(parts[1]))
    }

    public func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}

public enum KeychainError: Error, Equatable {
    case unhandled(OSStatus)
}
