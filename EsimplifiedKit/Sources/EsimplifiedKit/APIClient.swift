import Foundation

public protocol APIClient: Sendable {
    func get<T: Decodable>(_ path: String, query: [String: String], as type: T.Type) async throws -> T
}

public final class LiveAPIClient: APIClient {
    private let host: String
    private let accessToken: String
    private let session: URLSession

    public init(host: String, accessToken: String, session: URLSession = .shared) {
        self.host = host
        self.accessToken = accessToken
        self.session = session
    }

    public func get<T: Decodable>(_ path: String, query: [String: String], as type: T.Type) async throws -> T {
        guard var components = URLComponents(string: host) else { throw APIError.unreachable }
        components.path = path
        if !query.isEmpty {
            // Sort for deterministic URL ordering (Dictionary iteration order is undefined).
            components.queryItems = query.sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.unreachable }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.unreachable
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.unreachable }
        switch http.statusCode {
        case 200...299:
            do { return try JSONDecoder().decode(T.self, from: data) }
            catch { throw APIError.decoding }
        case 401, 403:
            throw APIError.authExpired
        case 404:
            throw APIError.notFound
        default:
            throw APIError.server(http.statusCode)
        }
    }
}
