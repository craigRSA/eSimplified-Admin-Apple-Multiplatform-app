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
    private let accessToken: String
    private let session: URLSession

    public init(host: String, accessToken: String, session: URLSession = .shared) {
        self.host = host
        self.accessToken = accessToken
        self.session = session
    }

    public func status() async throws -> Bool {
        let json = try await send("GET", "/2fa/status/", form: nil)
        return (json["totp_enabled"] as? Bool) ?? false
    }

    public func beginSetup() async throws -> TOTPSetup {
        let json = try await send("POST", "/2fa/setup/", form: [:])
        guard let url = json["otpauth_url"] as? String else { throw APIError.decoding }
        return TOTPSetup(otpauthURL: url, secret: json["secret"] as? String)
    }

    public func verify(code: String) async throws {
        _ = try await send("POST", "/2fa/verify/", form: ["code": code])
    }

    public func disable(code: String) async throws {
        _ = try await send("POST", "/2fa/disable/", form: ["code": code])
    }

    private func send(_ method: String, _ path: String, form: [String: String]?) async throws -> [String: Any] {
        guard var components = URLComponents(string: host) else { throw APIError.unreachable }
        components.path = path
        guard let url = components.url else { throw APIError.unreachable }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let form {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = LiveAuthClient.formEncode(form).data(using: .utf8)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.unreachable
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.authExpired
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
