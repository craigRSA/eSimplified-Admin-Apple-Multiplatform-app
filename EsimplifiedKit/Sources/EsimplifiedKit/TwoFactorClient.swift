import Foundation

public struct TOTPSetup: Equatable, Sendable {
    public let otpauthURL: String
    public let secret: String?
    public init(otpauthURL: String, secret: String?) {
        self.otpauthURL = otpauthURL
        self.secret = secret
    }
}

public protocol TwoFactorClient: Sendable {
    func status() async throws -> Bool
    func beginSetup() async throws -> TOTPSetup
    func verify(code: String) async throws
    func disable(code: String) async throws
}

public final class LiveTwoFactorClient: TwoFactorClient {
    private let host: String
    private let tokenProvider: AccessTokenProviding
    private let session: URLSession

    public init(host: String, tokenProvider: AccessTokenProviding, session: URLSession = .shared) {
        self.host = host
        self.tokenProvider = tokenProvider
        self.session = session
    }

    public convenience init(host: String, accessToken: String, session: URLSession = .shared) {
        self.init(host: host, tokenProvider: StaticTokenProvider(accessToken), session: session)
    }

    public func status() async throws -> Bool {
        let json = try await send("GET", "/api/2fa/status/", json: nil)
        // `enabled` is the guaranteed field; `totp_enabled` is preferred but
        // optional (mirrors the web fallback chain in two-factor-card.tsx).
        return (json["totp_enabled"] as? Bool) ?? (json["enabled"] as? Bool) ?? false
    }

    public func beginSetup() async throws -> TOTPSetup {
        // Bodyless POST, matching the web app's setup2FA().
        let json = try await send("POST", "/api/2fa/setup/", json: nil)
        guard let url = json["otpauth_url"] as? String else { throw APIError.decoding }
        return TOTPSetup(otpauthURL: url, secret: json["secret"] as? String)
    }

    public func verify(code: String) async throws {
        _ = try await send("POST", "/api/2fa/verify/", json: ["code": code])
    }

    public func disable(code: String) async throws {
        _ = try await send("POST", "/api/2fa/disable/", json: ["code": code])
    }

    // Endpoints take a JSON body with `{ "code": ... }` (matches the web app).
    private func send(_ method: String, _ path: String, json: [String: Any]?) async throws -> [String: Any] {
        let token = try await tokenProvider.validAccessToken()

        guard var components = URLComponents(string: host) else { throw APIError.unreachable }
        components.path = path
        guard let url = components.url else { throw APIError.unreachable }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: json)
        }

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
            break
        case 401:
            throw APIError.authExpired
        case 404:
            throw APIError.notFound
        default:
            // A wrong code (400), permission (403), or 5xx must surface the real
            // status + server reason — not masquerade as an expired session.
            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = (body?.isEmpty == false) ? String(body!.prefix(300)) : nil
            throw APIError.requestFailed(status: http.statusCode, serverMessage: message)
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
