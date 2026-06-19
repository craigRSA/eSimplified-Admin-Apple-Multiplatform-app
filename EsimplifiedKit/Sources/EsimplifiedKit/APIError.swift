import Foundation

public enum APIError: Error, Equatable, Sendable {
    case authExpired
    case unreachable
    case notFound
    case server(Int)
    case decoding
}
