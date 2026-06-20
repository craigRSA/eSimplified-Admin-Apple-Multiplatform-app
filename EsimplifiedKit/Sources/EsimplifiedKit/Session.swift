import Foundation

public struct Session: Codable, Equatable, Sendable {
    public let host: String
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let scopes: [String]
    public let accountType: String

    public init(host: String, accessToken: String, refreshToken: String,
                expiresAt: Date, scopes: [String], accountType: String) {
        self.host = host
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scopes = scopes
        self.accountType = accountType
    }

    /// True when the token carries `<resource>:read`.
    public func hasScope(_ resource: String) -> Bool {
        scopes.contains("\(resource):read")
    }
}

/// Sendable so it can cross the @MainActor (AdminAppModel) ↔ actor (SessionManager)
/// boundary safely — the same store instance is held by both.
public protocol SessionStore: Sendable {
    func save(_ session: Session) throws
    func load() throws -> Session?
    func clear() throws
    func saveTrustedDeviceToken(_ token: String, host: String) throws
    func trustedDeviceToken(host: String) throws -> String?
    func setBiometricEnabled(_ enabled: Bool) throws
    func biometricEnabled() -> Bool
}

public final class InMemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: Session?
    private var trusted: [String: String] = [:]
    private var biometric = false

    public init() {}

    public func save(_ session: Session) throws { lock.withLock { self.session = session } }
    public func load() throws -> Session? { lock.withLock { session } }
    public func clear() throws { lock.withLock { session = nil } }
    public func saveTrustedDeviceToken(_ token: String, host: String) throws { lock.withLock { trusted[host] = token } }
    public func trustedDeviceToken(host: String) throws -> String? { lock.withLock { trusted[host] } }
    public func setBiometricEnabled(_ enabled: Bool) throws { lock.withLock { biometric = enabled } }
    public func biometricEnabled() -> Bool { lock.withLock { biometric } }
}
