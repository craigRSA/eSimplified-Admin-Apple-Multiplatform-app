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

public protocol SessionStore {
    func save(_ session: Session) throws
    func load() throws -> Session?
    func clear() throws
    func saveTrustedDeviceToken(_ token: String, host: String) throws
    func trustedDeviceToken(host: String) throws -> String?
    func setBiometricEnabled(_ enabled: Bool) throws
    func biometricEnabled() -> Bool
}

public final class InMemorySessionStore: SessionStore {
    private var session: Session?
    private var trusted: [String: String] = [:]
    private var biometric = false

    public init() {}

    public func save(_ session: Session) throws { self.session = session }
    public func load() throws -> Session? { session }
    public func clear() throws { session = nil }
    public func saveTrustedDeviceToken(_ token: String, host: String) throws { trusted[host] = token }
    public func trustedDeviceToken(host: String) throws -> String? { trusted[host] }
    public func setBiometricEnabled(_ enabled: Bool) throws { biometric = enabled }
    public func biometricEnabled() -> Bool { biometric }
}
