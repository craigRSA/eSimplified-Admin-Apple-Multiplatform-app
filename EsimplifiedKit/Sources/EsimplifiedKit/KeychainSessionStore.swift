import Foundation
import Security

public final class KeychainSessionStore: SessionStore {
    private let service = "io.esimplified.admin"
    private let sessionAccount = "session"
    private let biometricAccount = "biometric-enabled"

    public init() {}

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
        try delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    private func read(account: String) throws -> Data? {
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
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.unhandled(status)
        }
        return data
    }

    private func delete(account: String) throws {
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
