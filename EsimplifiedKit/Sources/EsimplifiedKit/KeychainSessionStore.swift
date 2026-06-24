import Foundation
import Security

public final class KeychainSessionStore: SessionStore, @unchecked Sendable {
    private let service = "io.esimplified.admin"
    private let sessionAccount = "session"
    private let biometricAccount = "biometric-enabled"
    /// From the signed `keychain-access-groups` entitlement — shared with the widget.
    private let accessGroup: String?

    public init(accessGroup: String? = nil) {
        self.accessGroup = accessGroup ?? Self.resolvedAccessGroup()
    }

    public func save(_ session: Session) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        try write(data, account: sessionAccount)
    }

    public func load() throws -> Session? {
        guard let data = try read(account: sessionAccount) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Session.self, from: data)
    }

    public func clear() throws { try delete(account: sessionAccount) }

    public func saveTrustedDeviceToken(_ token: String, host: String) throws {
        try write(Data(token.utf8), account: trustedAccount(host))
    }

    public func trustedDeviceToken(host: String) throws -> String? {
        guard let data = try read(account: trustedAccount(host)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func trustedAccount(_ host: String) -> String { "trusted::\(host)" }

    public func setBiometricEnabled(_ enabled: Bool) throws {
        try write(Data([enabled ? 1 : 0]), account: biometricAccount)
    }

    public func biometricEnabled() -> Bool {
        (try? read(account: biometricAccount))??.first == 1  // empty/missing/corrupt data → disabled (safe default)
    }

    private func write(_ data: Data, account: String) throws {
        let query = itemQuery(account: account)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            #if os(macOS)
            // Data-protection keychain items share cleanly with the widget extension.
            add[kSecUseDataProtectionKeychain as String] = true
            #endif
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    private func read(account: String) throws -> Data? {
        var query = itemQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.unhandled(status)
        }
        return data
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(itemQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    /// Shared lookup attributes for one stored secret. Updates in place so macOS
    /// doesn't re-prompt after "Always Allow" on every token refresh.
    private func itemQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    /// First group from the target's signed entitlements (`io.esimplified.admin.shared`).
    private static func resolvedAccessGroup() -> String? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return (SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil) as? [String])?.first
    }
}

public enum KeychainError: Error, Equatable {
    case unhandled(OSStatus)
}
