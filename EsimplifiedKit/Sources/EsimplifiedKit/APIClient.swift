import Foundation

public protocol APIClient: Sendable {
    func get<T: Decodable>(_ path: String, query: [String: String], as type: T.Type) async throws -> T
}

public final class LiveAPIClient: APIClient {
    private let host: String
    private let tokenProvider: AccessTokenProviding
    private let session: URLSession

    public init(host: String, tokenProvider: AccessTokenProviding, session: URLSession = .shared) {
        self.host = host
        self.tokenProvider = tokenProvider
        self.session = session
    }

    /// Preserves the prior fixed-token call sites (and tests). A 401 surfaces as
    /// `authExpired` with no retry, exactly as before.
    public convenience init(host: String, accessToken: String, session: URLSession = .shared) {
        self.init(host: host, tokenProvider: StaticTokenProvider(accessToken), session: session)
    }

    public func get<T: Decodable>(_ path: String, query: [String: String], as type: T.Type) async throws -> T {
        let token = try await tokenProvider.validAccessToken()
        do {
            return try await perform(path, query: query, token: token, as: type)
        } catch APIError.authExpired {
            // Clock-skew / server-side expiry: refresh once and retry. A second
            // 401 (refresh token dead) propagates as authExpired.
            let fresh = try await tokenProvider.refreshedAccessToken(after: token)
            return try await perform(path, query: query, token: fresh, as: type)
        }
    }

    private func perform<T: Decodable>(_ path: String, query: [String: String],
                                       token: String, as type: T.Type) async throws -> T {
        guard var components = URLComponents(string: host) else { throw APIError.unreachable }
        components.path = path
        if !query.isEmpty {
            // URLComponents leaves `+` unencoded in query values; servers decode
            // that as a space (form-urlencoded rules). Reuse the auth client's
            // RFC 3986 encoder so emails like `user+tag@…` survive intact.
            components.percentEncodedQuery = LiveAuthClient.formEncode(query)
        }
        guard let url = components.url else { throw APIError.unreachable }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            // The caller's Task was cancelled (e.g. the view went away on
            // navigation) — that's not a connectivity failure.
            throw CancellationError()
        } catch {
            throw APIError.unreachable
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.unreachable }
        switch http.statusCode {
        case 200...299:
            do { return try JSONDecoder().decode(T.self, from: data) }
            catch { throw APIError.decoding }
        case 401:
            throw APIError.authExpired
        case 404:
            throw APIError.notFound
        default:
            // Surface the real status + server reason rather than masking
            // everything as "session expired".
            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = (body?.isEmpty == false) ? String(body!.prefix(300)) : nil
            throw APIError.requestFailed(status: http.statusCode, serverMessage: message)
        }
    }
}
