import Foundation

public enum APIError: Error, Equatable, Sendable {
    case authExpired
    case unreachable
    case notFound
    case server(Int)
    case decoding
    /// A non-2xx response carrying the backend's own error text (status + message),
    /// so callers can surface what the server actually said rather than a guess.
    case requestFailed(status: Int, serverMessage: String?)
}
