import Foundation

public struct Credentials: Equatable, Sendable {
    public let host: String
    public let token: String

    public init(host: String, token: String) {
        self.host = host
        self.token = token
    }
}

public protocol CredentialStore {
    func save(_ credentials: Credentials) throws
    func load() throws -> Credentials?
    func clear() throws
}

public final class InMemoryCredentialStore: CredentialStore {
    private var stored: Credentials?

    public init() {}

    public func save(_ credentials: Credentials) throws { stored = credentials }
    public func load() throws -> Credentials? { stored }
    public func clear() throws { stored = nil }
}
