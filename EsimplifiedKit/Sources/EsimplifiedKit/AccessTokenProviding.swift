import Foundation

/// Vends a currently-valid OAuth access token. The request layer calls
/// `validAccessToken()` before each request, and `refreshedAccessToken(after:)`
/// once on a 401 (clock-skew defense). Implemented by `SessionManager`.
public protocol AccessTokenProviding: Sendable {
    func validAccessToken() async throws -> String
    /// Force a refresh because a request using `staleToken` got a 401. If another
    /// caller already replaced `staleToken`, returns the current token without
    /// refreshing again. Throws `APIError.authExpired` if refresh is impossible.
    func refreshedAccessToken(after staleToken: String) async throws -> String
}

/// A fixed token that cannot refresh — preserves the pre-existing
/// `LiveAPIClient(host:accessToken:)` behavior (a 401 surfaces as `authExpired`,
/// no retry). Used for tests and any fixed-token call site.
public struct StaticTokenProvider: AccessTokenProviding {
    private let token: String
    public init(_ token: String) { self.token = token }
    public func validAccessToken() async throws -> String {
        if token.isEmpty { throw APIError.authExpired }
        return token
    }
    public func refreshedAccessToken(after staleToken: String) async throws -> String {
        throw APIError.authExpired
    }
}
