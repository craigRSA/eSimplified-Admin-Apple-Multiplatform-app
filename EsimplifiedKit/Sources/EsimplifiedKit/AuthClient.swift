import Foundation

public enum AuthResult: Equatable, Sendable {
    case session(Session)
    case needs2FA(token: String)
}

public protocol AuthClient: Sendable {
    func login(username: String, password: String, host: String,
               trustedDeviceToken: String?) async throws -> AuthResult
    func verify2FA(host: String, twoFAToken: String, code: String,
                   rememberDevice: Bool) async throws -> (Session, trustedDeviceToken: String?)
    func refresh(host: String, refreshToken: String) async throws -> Session
}

public final class LiveAuthClient: AuthClient {
    private let clientID: String
    private let clientSecret: String
    private let session: URLSession

    public init(clientID: String, clientSecret: String, session: URLSession = .shared) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.session = session
    }

    public func login(username: String, password: String, host: String,
                      trustedDeviceToken: String?) async throws -> AuthResult {
        var headers: [String: String] = [:]
        if let trustedDeviceToken { headers["X-Trusted-Device"] = trustedDeviceToken }
        let json = try await post(host: host, path: "/auth/token/", extraHeaders: headers, form: [
            "grant_type": "password", "username": username, "password": password,
        ])
        if (json["requires_2fa"] as? Bool) == true {
            guard let token = json["2fa_token"] as? String, !token.isEmpty else { throw APIError.decoding }
            return .needs2FA(token: token)
        }
        return .session(try Self.makeSession(from: json, host: host))
    }

    public func verify2FA(host: String, twoFAToken: String, code: String,
                          rememberDevice: Bool) async throws -> (Session, trustedDeviceToken: String?) {
        // The 2FA endpoint takes a JSON body (not form), no Basic auth — the
        // two_fa_token is the credential. Field names must match the backend.
        let json = try await postJSON(host: host, path: "/auth/token/2fa/", body: [
            "two_fa_token": twoFAToken, "code": code, "remember_device": rememberDevice,
        ])
        return (try Self.makeSession(from: json, host: host), json["trusted_device_token"] as? String)
    }

    public func refresh(host: String, refreshToken: String) async throws -> Session {
        let json = try await post(host: host, path: "/auth/token/", extraHeaders: [:], form: [
            "grant_type": "refresh_token", "refresh_token": refreshToken,
        ])
        return try Self.makeSession(from: json, host: host)
    }

    // MARK: - helpers

    private func post(host: String, path: String, extraHeaders: [String: String],
                      form: [String: String]) async throws -> [String: Any] {
        guard var components = URLComponents(string: host) else { throw APIError.unreachable }
        components.path = path
        guard let url = components.url else { throw APIError.unreachable }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let creds = Data("\(clientID):\(clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(creds)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = Self.formEncode(form).data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.unreachable }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.requestFailed(status: http.statusCode, serverMessage: Self.serverMessage(from: data))
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decoding
        }
        return object
    }

    /// JSON POST without client Basic auth — used by the 2FA endpoint, which
    /// authenticates via the two_fa_token in the body, not the client creds.
    private func postJSON(host: String, path: String, body: [String: Any]) async throws -> [String: Any] {
        guard var components = URLComponents(string: host) else { throw APIError.unreachable }
        components.path = path
        guard let url = components.url else { throw APIError.unreachable }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.unreachable }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.requestFailed(status: http.statusCode, serverMessage: Self.serverMessage(from: data))
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decoding
        }
        return object
    }

    /// Pull a human-readable message out of an OAuth2/DRF error body
    /// (`error_description`, `detail`, or `error`); fall back to raw text.
    private static func serverMessage(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let m = object["error_description"] as? String { return m }
            if let m = object["detail"] as? String { return m }
            if let m = object["error"] as? String { return m }
        }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : nil
    }

    private static func makeSession(from json: [String: Any], host: String) throws -> Session {
        guard let access = json["access_token"] as? String else { throw APIError.decoding }
        let refresh = (json["refresh_token"] as? String) ?? ""
        let expiresIn = (json["expires_in"] as? Int) ?? Int((json["expires_in"] as? String) ?? "0") ?? 0
        let accountType = (json["account_type"] as? String) ?? "human"
        return Session(host: host, accessToken: access, refreshToken: refresh,
                       expiresAt: Date(timeIntervalSinceNow: TimeInterval(expiresIn)),
                       scopes: parseScopes(json["scope"]), accountType: accountType)
    }

    private static func parseScopes(_ raw: Any?) -> [String] {
        if let string = raw as? String { return string.split(separator: " ").map(String.init) }
        if let array = raw as? [String] { return array }
        return []
    }

    /// `application/x-www-form-urlencoded` encoding: percent-encode everything
    /// except RFC 3986 unreserved characters. Critically this encodes `%`, `@`,
    /// `+`, `&`, `=`, and spaces, so credentials containing them survive intact.
    /// Internal (not private) so the encoding is unit-testable directly.
    static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.sorted { $0.key < $1.key }.map { key, value in
            let ek = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let ev = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
    }
}
