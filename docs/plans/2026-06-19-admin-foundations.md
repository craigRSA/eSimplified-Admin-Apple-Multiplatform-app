# eSimplified Admin — Foundations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The auth + shell foundation of the native eSimplified Admin app — a reusable Bearer API client, OAuth2 password-grant login with TOTP 2FA (challenge + enrollment), session storage in the Keychain, and an adaptive (Mac/iPad/iPhone) navigation shell whose sections are gated by token scopes.

**Architecture:** All non-UI logic is added to the existing `EsimplifiedKit` Swift package (already `.macOS(.v14)` + `.iOS(.v17)`), unit-tested from the command line with the existing `MockURLProtocol`/`InMemoryCredentialStore` harness. A new SwiftUI multiplatform app target `eSimplifiedAdmin` (added to `Esimplified.xcodeproj`) holds the adaptive UI and imports `EsimplifiedKit`. Spec: `docs/specs/2026-06-19-esimplified-admin-native-design.md`.

**Tech Stack:** Swift 5.9+, SwiftUI, Foundation `URLSession`/`Codable`, CoreImage (`CIQRCodeGenerator`), macOS Keychain Services, XCTest. No third-party dependencies.

## Global Constraints

- Platform floor: **macOS 14.0 / iOS 17.0** (`@Observable`). Swift tools 5.9+.
- Money values always `Decimal`; never `Double`/`Float` for storage or comparison.
- API decimal fields may arrive as JSON strings or numbers — use the existing `FlexibleDecimal`.
- No third-party dependencies — Foundation / SwiftUI / CoreImage / XCTest only.
- Tokens (access, refresh, trusted-device) live only in the **macOS Keychain**, never in `UserDefaults` or plaintext.
- `CLIENT_ID` / `CLIENT_SECRET` are **injected** into clients (never hardcoded in package source); the app supplies them from a build setting.
- Auth endpoints: `POST {host}/auth/token/` (password grant + refresh), `POST {host}/auth/token/2fa/` (2FA challenge). 2FA mgmt: `GET /2fa/status/`, `POST /2fa/setup/`, `POST /2fa/verify/`, `POST /2fa/disable/`. API calls send `Authorization: Bearer <access_token>`; auth calls send `Authorization: Basic base64(CLIENT_ID:CLIENT_SECRET)`.
- TDD for all engine code: failing test → see it fail → implement → see it pass → commit.

---

## File Structure

```
EsimplifiedKit/Sources/EsimplifiedKit/
  Session.swift            # Session model + SessionStore protocol + InMemorySessionStore
  KeychainSessionStore.swift  # real Keychain-backed SessionStore (+ trusted-device token)
  APIError.swift           # shared typed error for API + auth clients
  APIClient.swift          # APIClient protocol + LiveAPIClient (Bearer JSON)
  AuthClient.swift         # AuthClient + AuthResult + password grant / refresh / 2FA verify
  TwoFactorClient.swift    # TwoFactorClient + TOTP status/setup/verify/disable
EsimplifiedKit/Tests/EsimplifiedKitTests/
  SessionStoreTests.swift
  APIClientTests.swift
  AuthClientTests.swift
  TwoFactorClientTests.swift
eSimplifiedAdmin/          # new SwiftUI multiplatform app target
  eSimplifiedAdminApp.swift   # @main, AppModel, RootView
  LoginView.swift             # host + username + password, then TOTP code step
  TwoFactorSetupView.swift    # enroll TOTP: QR (CoreImage) + secret + verify
  AdminShell.swift            # NavigationSplitView, scope-gated sections, placeholders
  eSimplifiedAdmin.entitlements      # macOS: sandbox + network.client
  eSimplifiedAdmin-iOS.entitlements  # iOS: (network is default; file kept for parity/future)
```

The split keeps each client focused on one endpoint family; `APIError` is shared so callers map one error type. Tasks 1–4 are pure-engine (TDD); Tasks 5–8 build the app target (verified by build + run).

---

### Task 1: Session model + Keychain session storage

**Files:**
- Create: `EsimplifiedKit/Sources/EsimplifiedKit/Session.swift`
- Create: `EsimplifiedKit/Sources/EsimplifiedKit/KeychainSessionStore.swift`
- Test: `EsimplifiedKit/Tests/EsimplifiedKitTests/SessionStoreTests.swift`

**Interfaces:**
- Produces:
  - `struct Session: Equatable, Sendable { host, accessToken, refreshToken: String; expiresAt: Date; scopes: [String]; accountType: String }` with memberwise `init` and `func hasScope(_ resource: String) -> Bool` (true when `"<resource>:read"` is in `scopes`).
  - `protocol SessionStore { func save(_:) throws; func load() throws -> Session?; func clear() throws; func saveTrustedDeviceToken(_ token: String, host: String) throws; func trustedDeviceToken(host: String) throws -> String? }`
  - `final class InMemorySessionStore: SessionStore`
  - `final class KeychainSessionStore: SessionStore`

- [ ] **Step 1: Write the failing test**

Create `EsimplifiedKit/Tests/EsimplifiedKitTests/SessionStoreTests.swift`:

```swift
import XCTest
@testable import EsimplifiedKit

final class SessionStoreTests: XCTestCase {
    private func sampleSession() -> Session {
        Session(host: "https://live.esimplified.io",
                accessToken: "acc-1", refreshToken: "ref-1",
                expiresAt: Date(timeIntervalSince1970: 1_750_000_000),
                scopes: ["statistics:read", "order:read"],
                accountType: "human")
    }

    func test_inMemory_save_load_clear() throws {
        let store = InMemorySessionStore()
        XCTAssertNil(try store.load())
        try store.save(sampleSession())
        XCTAssertEqual(try store.load(), sampleSession())
        try store.clear()
        XCTAssertNil(try store.load())
    }

    func test_hasScope_matches_read_scope() {
        let s = sampleSession()
        XCTAssertTrue(s.hasScope("order"))
        XCTAssertFalse(s.hasScope("inventory"))
    }

    func test_inMemory_trusted_device_token_per_host() throws {
        let store = InMemorySessionStore()
        try store.saveTrustedDeviceToken("td-1", host: "https://a.example.com")
        XCTAssertEqual(try store.trustedDeviceToken(host: "https://a.example.com"), "td-1")
        XCTAssertNil(try store.trustedDeviceToken(host: "https://b.example.com"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/xcode/eSimPulse/EsimplifiedKit && swift test --filter SessionStoreTests`
Expected: FAIL — `cannot find 'Session'/'InMemorySessionStore' in scope`.

- [ ] **Step 3: Implement Session + protocol + in-memory store**

Create `EsimplifiedKit/Sources/EsimplifiedKit/Session.swift`:

```swift
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
}

public final class InMemorySessionStore: SessionStore {
    private var session: Session?
    private var trusted: [String: String] = [:]

    public init() {}

    public func save(_ session: Session) throws { self.session = session }
    public func load() throws -> Session? { session }
    public func clear() throws { session = nil }
    public func saveTrustedDeviceToken(_ token: String, host: String) throws { trusted[host] = token }
    public func trustedDeviceToken(host: String) throws -> String? { trusted[host] }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/xcode/eSimPulse/EsimplifiedKit && swift test --filter SessionStoreTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Implement the Keychain-backed store**

Create `EsimplifiedKit/Sources/EsimplifiedKit/KeychainSessionStore.swift`. Session is JSON-encoded under one generic-password item; trusted-device tokens are stored per-host under a namespaced account.

```swift
import Foundation
import Security

public final class KeychainSessionStore: SessionStore {
    private let service = "io.esimplified.admin"
    private let sessionAccount = "session"

    public init() {}

    public func save(_ session: Session) throws {
        let data = try JSONEncoder().encode(session)
        try write(data, account: sessionAccount)
    }

    public func load() throws -> Session? {
        guard let data = try read(account: sessionAccount) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    public func clear() throws { try delete(account: sessionAccount) }

    public func saveTrustedDeviceToken(_ token: String, host: String) throws {
        try write(Data(token.utf8), account: trustedAccount(host))
    }

    public func trustedDeviceToken(host: String) throws -> String? {
        guard let data = try read(account: trustedAccount(host)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func trustedAccount(_ host: String) -> String { "trusted::\(host)" }

    private func write(_ data: Data, account: String) throws {
        try delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    private func read(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.unhandled(status)
        }
        return data
    }

    private func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}
```

> Note: `KeychainError` already exists in `KeychainCredentialStore.swift`; reuse it. `KeychainSessionStore` is verified manually in the app (not unit-tested), matching the existing `KeychainCredentialStore` convention.

- [ ] **Step 6: Run the full package build + suite**

Run: `cd ~/xcode/eSimPulse/EsimplifiedKit && swift build && swift test`
Expected: `Build complete!` and all tests pass (prior 15 + 3 new = 18).

- [ ] **Step 7: Commit**

```bash
cd ~/xcode/eSimPulse && git add EsimplifiedKit && \
  git commit -m "feat: Session model + Keychain session storage"
```

---

### Task 2: APIError + generalized Bearer API client

**Files:**
- Create: `EsimplifiedKit/Sources/EsimplifiedKit/APIError.swift`
- Create: `EsimplifiedKit/Sources/EsimplifiedKit/APIClient.swift`
- Test: `EsimplifiedKit/Tests/EsimplifiedKitTests/APIClientTests.swift`

**Interfaces:**
- Consumes: `MockURLProtocol` (existing test helper).
- Produces:
  - `enum APIError: Error, Equatable, Sendable { case authExpired; case unreachable; case notFound; case server(Int); case decoding }`
  - `protocol APIClient: Sendable { func get<T: Decodable>(_ path: String, query: [String: String], as type: T.Type) async throws -> T }`
  - `final class LiveAPIClient: APIClient` with `init(host: String, accessToken: String, session: URLSession = .shared)`. Builds `{host}{path}` + query, sets `Authorization: Bearer <token>` + `Accept: application/json`; maps 200→decode (decode failure→`.decoding`), 401/403→`.authExpired`, 404→`.notFound`, other ≥400→`.server(code)`, transport failure→`.unreachable`.

- [ ] **Step 1: Write the failing tests**

Create `EsimplifiedKit/Tests/EsimplifiedKitTests/APIClientTests.swift`:

```swift
import XCTest
@testable import EsimplifiedKit

private struct Widget: Decodable, Equatable { let id: Int; let name: String }

final class APIClientTests: XCTestCase {
    override func tearDown() { MockURLProtocol.handler = nil; super.tearDown() }

    private func makeClient() -> LiveAPIClient {
        LiveAPIClient(host: "https://live.esimplified.io", accessToken: "tok-9",
                      session: MockURLProtocol.makeSession())
    }

    func test_get_builds_url_query_and_bearer_then_decodes() async throws {
        var captured: URLRequest?
        MockURLProtocol.handler = { req in
            captured = req
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"id":7,"name":"a"}"#.utf8))
        }
        let w: Widget = try await makeClient().get("/api/widgets/1/", query: ["q": "x"], as: Widget.self)
        XCTAssertEqual(w, Widget(id: 7, name: "a"))
        XCTAssertEqual(captured?.url?.absoluteString,
                       "https://live.esimplified.io/api/widgets/1/?q=x")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer tok-9")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func test_get_maps_401_to_authExpired() async {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        await assertAPIError(.authExpired) { _ = try await self.makeClient().get("/x/", query: [:], as: Widget.self) }
    }

    func test_get_maps_404_to_notFound() async {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        await assertAPIError(.notFound) { _ = try await self.makeClient().get("/x/", query: [:], as: Widget.self) }
    }

    func test_get_maps_malformed_body_to_decoding() async {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("nope".utf8))
        }
        await assertAPIError(.decoding) { _ = try await self.makeClient().get("/x/", query: [:], as: Widget.self) }
    }

    func test_get_maps_transport_failure_to_unreachable() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await assertAPIError(.unreachable) { _ = try await self.makeClient().get("/x/", query: [:], as: Widget.self) }
    }

    private func assertAPIError(_ expected: APIError, _ block: () async throws -> Void,
                                file: StaticString = #filePath, line: UInt = #line) async {
        do { try await block(); XCTFail("expected \(expected)", file: file, line: line) }
        catch let e as APIError { XCTAssertEqual(e, expected, file: file, line: line) }
        catch { XCTFail("unexpected \(error)", file: file, line: line) }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ~/xcode/eSimPulse/EsimplifiedKit && swift test --filter APIClientTests`
Expected: FAIL — `cannot find type 'LiveAPIClient'/'APIError' in scope`.

- [ ] **Step 3: Implement APIError + LiveAPIClient**

Create `EsimplifiedKit/Sources/EsimplifiedKit/APIError.swift`:

```swift
import Foundation

public enum APIError: Error, Equatable, Sendable {
    case authExpired
    case unreachable
    case notFound
    case server(Int)
    case decoding
}
```

Create `EsimplifiedKit/Sources/EsimplifiedKit/APIClient.swift`:

```swift
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
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.unreachable }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw APIError.unreachable }

        guard let http = response as? HTTPURLResponse else { throw APIError.unreachable }
        switch http.statusCode {
        case 200...299:
            do { return try JSONDecoder().decode(T.self, from: data) }
            catch { throw APIError.decoding }
        case 401, 403: throw APIError.authExpired
        case 404: throw APIError.notFound
        default: throw APIError.server(http.statusCode)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ~/xcode/eSimPulse/EsimplifiedKit && swift test --filter APIClientTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/xcode/eSimPulse && git add EsimplifiedKit && \
  git commit -m "feat: APIError + generalized Bearer APIClient"
```

---

### Task 3: AuthClient — password grant, refresh, 2FA challenge

**Files:**
- Create: `EsimplifiedKit/Sources/EsimplifiedKit/AuthClient.swift`
- Test: `EsimplifiedKit/Tests/EsimplifiedKitTests/AuthClientTests.swift`

**Interfaces:**
- Consumes: `Session` (Task 1), `APIError` (Task 2), `MockURLProtocol`.
- Produces:
  - `enum AuthResult: Equatable, Sendable { case session(Session); case needs2FA(token: String) }`
  - `protocol AuthClient: Sendable { func login(username: String, password: String, host: String, trustedDeviceToken: String?) async throws -> AuthResult; func verify2FA(host: String, twoFAToken: String, code: String, rememberDevice: Bool) async throws -> (Session, trustedDeviceToken: String?); func refresh(host: String, refreshToken: String) async throws -> Session }`
  - `final class LiveAuthClient: AuthClient` with `init(clientID: String, clientSecret: String, session: URLSession = .shared)`.

**Notes:** `login` POSTs form `grant_type=password&username&password` to `{host}/auth/token/` with `Authorization: Basic base64(clientID:clientSecret)`, `Content-Type: application/x-www-form-urlencoded`, and `X-Trusted-Device` when a token is supplied. A response with `requires_2fa==true` returns `.needs2FA(token: json["2fa_token"])`; otherwise `.session(...)`. `verify2FA` POSTs `2fa_token` + `code` (+ `remember_device`) to `{host}/auth/token/2fa/` and returns the session plus any `trusted_device_token` from the body. `refresh` POSTs `grant_type=refresh_token&refresh_token=…`. All map transport failure to `APIError.unreachable` and non-2xx to `APIError.authExpired`.

- [ ] **Step 1: Write the failing tests**

Create `EsimplifiedKit/Tests/EsimplifiedKitTests/AuthClientTests.swift`:

```swift
import XCTest
@testable import EsimplifiedKit

final class AuthClientTests: XCTestCase {
    override func tearDown() { MockURLProtocol.handler = nil; super.tearDown() }

    private func makeClient() -> LiveAuthClient {
        LiveAuthClient(clientID: "cid", clientSecret: "csec", session: MockURLProtocol.makeSession())
    }

    private func body(_ json: String, _ status: Int = 200) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { req in (HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(json.utf8)) }
    }

    func test_login_success_returns_session_with_scopes() async throws {
        var captured: URLRequest?
        var bodyData = Data()
        MockURLProtocol.handler = { req in
            captured = req
            bodyData = req.httpBody ?? Data() // see note below
            let json = #"{"access_token":"acc","refresh_token":"ref","token_type":"Bearer","expires_in":3600,"scope":"statistics:read order:read","account_type":"human"}"#
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        let result = try await makeClient().login(username: "u", password: "p",
                                                   host: "https://live.esimplified.io", trustedDeviceToken: nil)
        guard case let .session(s) = result else { return XCTFail("expected session") }
        XCTAssertEqual(s.accessToken, "acc")
        XCTAssertEqual(s.scopes, ["statistics:read", "order:read"])
        XCTAssertEqual(s.accountType, "human")
        XCTAssertEqual(captured?.url?.absoluteString, "https://live.esimplified.io/auth/token/")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"),
                       "Basic " + Data("cid:csec".utf8).base64EncodedString())
        _ = bodyData
    }

    func test_login_requires_2fa_returns_needs2FA() async throws {
        MockURLProtocol.handler = body(#"{"requires_2fa":true,"2fa_token":"tok-2fa"}"#)
        let result = try await makeClient().login(username: "u", password: "p",
                                                  host: "https://h.io", trustedDeviceToken: nil)
        XCTAssertEqual(result, .needs2FA(token: "tok-2fa"))
    }

    func test_login_sends_trusted_device_header_when_present() async throws {
        var captured: URLRequest?
        MockURLProtocol.handler = { req in
            captured = req
            let json = #"{"access_token":"a","refresh_token":"r","expires_in":60,"scope":"order:read","account_type":"human"}"#
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        _ = try await makeClient().login(username: "u", password: "p", host: "https://h.io", trustedDeviceToken: "td-7")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "X-Trusted-Device"), "td-7")
    }

    func test_verify2FA_returns_session_and_trusted_token() async throws {
        MockURLProtocol.handler = body(#"{"access_token":"a2","refresh_token":"r2","expires_in":3600,"scope":"order:read","account_type":"human","trusted_device_token":"td-new"}"#)
        let (s, td) = try await makeClient().verify2FA(host: "https://h.io", twoFAToken: "tok", code: "123456", rememberDevice: true)
        XCTAssertEqual(s.accessToken, "a2")
        XCTAssertEqual(td, "td-new")
    }

    func test_refresh_returns_new_session() async throws {
        MockURLProtocol.handler = body(#"{"access_token":"a3","refresh_token":"r3","expires_in":3600,"scope":"order:read","account_type":"human"}"#)
        let s = try await makeClient().refresh(host: "https://h.io", refreshToken: "r2")
        XCTAssertEqual(s.accessToken, "a3")
    }

    func test_login_non_2xx_maps_to_authExpired() async {
        MockURLProtocol.handler = body("{}", 401)
        do {
            _ = try await makeClient().login(username: "u", password: "p", host: "https://h.io", trustedDeviceToken: nil)
            XCTFail("expected throw")
        } catch let e as APIError { XCTAssertEqual(e, .authExpired) }
        catch { XCTFail("unexpected \(error)") }
    }
}
```

> Note on `req.httpBody`: under `URLSession`, a POST body set via `httpBody` is preserved on the request seen by `MockURLProtocol`; the `bodyData` capture above is illustrative and not asserted (it is discarded with `_ = bodyData`). Header and URL assertions are the meaningful checks.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ~/xcode/eSimPulse/EsimplifiedKit && swift test --filter AuthClientTests`
Expected: FAIL — `cannot find type 'LiveAuthClient'/'AuthResult' in scope`.

- [ ] **Step 3: Implement AuthClient**

Create `EsimplifiedKit/Sources/EsimplifiedKit/AuthClient.swift`:

```swift
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
        var extra = ["X-Trusted-Device": trustedDeviceToken].compactMapValues { $0 }
        let json = try await post(host: host, path: "/auth/token/", extraHeaders: extra, form: [
            "grant_type": "password", "username": username, "password": password,
        ])
        if (json["requires_2fa"] as? Bool) == true {
            let token = (json["2fa_token"] as? String) ?? ""
            return .needs2FA(token: token)
        }
        return .session(try Self.session(from: json, host: host))
        _ = extra
    }

    public func verify2FA(host: String, twoFAToken: String, code: String,
                          rememberDevice: Bool) async throws -> (Session, trustedDeviceToken: String?) {
        let json = try await post(host: host, path: "/auth/token/2fa/", extraHeaders: [:], form: [
            "2fa_token": twoFAToken, "code": code, "remember_device": rememberDevice ? "true" : "false",
        ])
        let s = try Self.session(from: json, host: host)
        return (s, json["trusted_device_token"] as? String)
    }

    public func refresh(host: String, refreshToken: String) async throws -> Session {
        let json = try await post(host: host, path: "/auth/token/", extraHeaders: [:], form: [
            "grant_type": "refresh_token", "refresh_token": refreshToken,
        ])
        return try Self.session(from: json, host: host)
    }

    // MARK: - helpers

    private func post(host: String, path: String, extraHeaders: [String: String],
                      form: [String: String]) async throws -> [String: Any] {
        guard var c = URLComponents(string: host) else { throw APIError.unreachable }
        c.path = path
        guard let url = c.url else { throw APIError.unreachable }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let creds = Data("\(clientID):\(clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(creds)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in extraHeaders { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = Self.formEncode(form).data(using: .utf8)

        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw APIError.unreachable }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.authExpired
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decoding
        }
        return obj
    }

    private static func session(from json: [String: Any], host: String) throws -> Session {
        guard let access = json["access_token"] as? String else { throw APIError.decoding }
        let refresh = (json["refresh_token"] as? String) ?? ""
        let expiresIn = (json["expires_in"] as? Int)
            ?? Int((json["expires_in"] as? String) ?? "0") ?? 0
        let accountType = (json["account_type"] as? String) ?? "human"
        return Session(host: host, accessToken: access, refreshToken: refresh,
                       expiresAt: Date(timeIntervalSinceNow: TimeInterval(expiresIn)),
                       scopes: parseScopes(json["scope"]), accountType: accountType)
    }

    private static func parseScopes(_ raw: Any?) -> [String] {
        if let s = raw as? String { return s.split(separator: " ").map(String.init) }
        if let a = raw as? [String] { return a }
        return []
    }

    private static func formEncode(_ form: [String: String]) -> String {
        var cs = CharacterSet.urlQueryAllowed
        cs.remove(charactersIn: "+&=")
        return form.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: cs) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: cs) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
    }
}
```

> Note: remove the stray `_ = extra` / unreachable-after-return lines if the compiler warns; they are not needed. Keep the body warning-free before committing.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ~/xcode/eSimPulse/EsimplifiedKit && swift test --filter AuthClientTests`
Expected: PASS (6 tests), output pristine (no warnings).

- [ ] **Step 5: Commit**

```bash
cd ~/xcode/eSimPulse && git add EsimplifiedKit && \
  git commit -m "feat: AuthClient — password grant, refresh, 2FA challenge"
```

---

### Task 4: TwoFactorClient — TOTP status / setup / verify / disable

**Files:**
- Create: `EsimplifiedKit/Sources/EsimplifiedKit/TwoFactorClient.swift`
- Test: `EsimplifiedKit/Tests/EsimplifiedKitTests/TwoFactorClientTests.swift`

**Interfaces:**
- Consumes: `APIError` (Task 2), `MockURLProtocol`.
- Produces:
  - `struct TOTPSetup: Equatable, Sendable { let otpauthURL: String; let secret: String? }`
  - `protocol TwoFactorClient: Sendable { func status() async throws -> Bool; func beginSetup() async throws -> TOTPSetup; func verify(code: String) async throws; func disable(code: String) async throws }`
  - `final class LiveTwoFactorClient: TwoFactorClient` with `init(host: String, accessToken: String, session: URLSession = .shared)`.

**Notes:** All calls are Bearer-authed against `{host}`. `status` GETs `/2fa/status/` → `totp_enabled` bool. `beginSetup` POSTs `/2fa/setup/` → `{ otpauth_url, secret? }`. `verify`/`disable` POST `/2fa/verify/` and `/2fa/disable/` with form `code=…`; non-2xx → `APIError.authExpired`. The TOTP secret may also be parsed from the `otpauth_url` query if `secret` is absent (handled in the view, Task 7 — the client just returns what the server sends).

- [ ] **Step 1: Write the failing tests**

Create `EsimplifiedKit/Tests/EsimplifiedKitTests/TwoFactorClientTests.swift`:

```swift
import XCTest
@testable import EsimplifiedKit

final class TwoFactorClientTests: XCTestCase {
    override func tearDown() { MockURLProtocol.handler = nil; super.tearDown() }

    private func makeClient() -> LiveTwoFactorClient {
        LiveTwoFactorClient(host: "https://h.io", accessToken: "tok", session: MockURLProtocol.makeSession())
    }

    func test_status_reads_totp_enabled() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.path, "/2fa/status/")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"totp_enabled":true}"#.utf8))
        }
        let enabled = try await makeClient().status()
        XCTAssertTrue(enabled)
    }

    func test_beginSetup_returns_otpauth_url_and_secret() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.url?.path, "/2fa/setup/")
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"method":"totp","otpauth_url":"otpauth://totp/e?secret=ABC","secret":"ABC"}"#.utf8))
        }
        let setup = try await makeClient().beginSetup()
        XCTAssertEqual(setup, TOTPSetup(otpauthURL: "otpauth://totp/e?secret=ABC", secret: "ABC"))
    }

    func test_verify_posts_code_and_succeeds_on_2xx() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.path, "/2fa/verify/")
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        try await makeClient().verify(code: "123456")
    }

    func test_verify_throws_authExpired_on_non_2xx() async {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        do { try await makeClient().verify(code: "000000"); XCTFail("expected throw") }
        catch let e as APIError { XCTAssertEqual(e, .authExpired) }
        catch { XCTFail("unexpected \(error)") }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ~/xcode/eSimPulse/EsimplifiedKit && swift test --filter TwoFactorClientTests`
Expected: FAIL — `cannot find type 'LiveTwoFactorClient'/'TOTPSetup' in scope`.

- [ ] **Step 3: Implement TwoFactorClient**

Create `EsimplifiedKit/Sources/EsimplifiedKit/TwoFactorClient.swift`:

```swift
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
        guard var c = URLComponents(string: host) else { throw APIError.unreachable }
        c.path = path
        guard let url = c.url else { throw APIError.unreachable }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let form {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = form.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        }
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw APIError.unreachable }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.authExpired
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass, then the whole suite**

Run: `cd ~/xcode/eSimPulse/EsimplifiedKit && swift test`
Expected: PASS — all tests (18 prior + 4 new = 22), output pristine.

- [ ] **Step 5: Commit**

```bash
cd ~/xcode/eSimPulse && git add EsimplifiedKit && \
  git commit -m "feat: TwoFactorClient — TOTP status/setup/verify/disable"
```

---

### Task 5: App target scaffold + AppModel + adaptive shell

This task creates the `eSimplifiedAdmin` multiplatform app target in `Esimplified.xcodeproj` and the navigation shell. Verified by build (macOS + iOS Simulator), not unit tests.

**Files:**
- Modify: `Esimplified.xcodeproj/project.pbxproj` (add target `eSimplifiedAdmin`, multiplatform: macOS + iOS, linking `EsimplifiedKit`; a shared scheme).
- Create: `eSimplifiedAdmin/eSimplifiedAdminApp.swift`
- Create: `eSimplifiedAdmin/AdminShell.swift`
- Create: `eSimplifiedAdmin/eSimplifiedAdmin.entitlements` (macOS: app-sandbox + network.client)

**Interfaces:**
- Consumes: `Session`, `SessionStore`, `KeychainSessionStore`, `LiveAPIClient`, `LiveAuthClient`, `LiveTwoFactorClient` (Tasks 1–4).
- Produces: `AppModel` (`@Observable @MainActor`), `AdminSection` enum, `RootView`, `AdminShell`.

- [ ] **Step 1: Add the multiplatform app target to the project**

Add a `PBXNativeTarget` `eSimplifiedAdmin` (productType `com.apple.product-type.application`). It must build for both macOS and iOS — set `SDKROOT = auto` and `SUPPORTED_PLATFORMS = "macosx iphoneos iphonesimulator"`, `MACOSX_DEPLOYMENT_TARGET = 14.0`, `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, `TARGETED_DEVICE_FAMILY = "1,2"`, `GENERATE_INFOPLIST_FILE = YES`, `PRODUCT_BUNDLE_IDENTIFIER = io.esimplified.admin`, `SWIFT_VERSION = 5.9`, `DEVELOPMENT_TEAM = 8GVFL9KS7M`, `CODE_SIGN_STYLE = Automatic`, and `CODE_SIGN_ENTITLEMENTS = eSimplifiedAdmin/eSimplifiedAdmin.entitlements` (entitlements apply on macOS; harmless on iOS). Add a `packageProductDependencies` entry on the existing local `EsimplifiedKit` package reference, a Sources build phase listing the three Swift files, a Frameworks phase linking `EsimplifiedKit`, and a shared scheme `eSimplifiedAdmin.xcscheme` under `xcshareddata/xcschemes/`. Inject client credentials via `INFOPLIST_KEY_` build settings: `INFOPLIST_KEY_ESPClientID` and `INFOPLIST_KEY_ESPClientSecret` (placeholder empty values committed; real values set locally, not in git).

> Follow the existing hand-authored pbxproj conventions in this project (UUID prefixes `E55…` for this target's objects to avoid collisions with E51–E54).

- [ ] **Step 2: Create the entitlements**

Create `eSimplifiedAdmin/eSimplifiedAdmin.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
</dict>
</plist>
```

- [ ] **Step 3: Create the app entry point + AppModel**

Create `eSimplifiedAdmin/eSimplifiedAdminApp.swift`:

```swift
import SwiftUI
import EsimplifiedKit

@main
struct eSimplifiedAdminApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        #endif
    }
}

@Observable
@MainActor
final class AppModel {
    let store: SessionStore
    private(set) var session: Session?

    // Client credentials injected from the build (Info.plist keys), never hardcoded.
    let clientID: String
    let clientSecret: String

    init(store: SessionStore = KeychainSessionStore()) {
        self.store = store
        self.clientID = (Bundle.main.object(forInfoDictionaryKey: "ESPClientID") as? String) ?? ""
        self.clientSecret = (Bundle.main.object(forInfoDictionaryKey: "ESPClientSecret") as? String) ?? ""
        self.session = try? store.load()
    }

    func authClient() -> LiveAuthClient {
        LiveAuthClient(clientID: clientID, clientSecret: clientSecret)
    }

    func adopt(_ session: Session) {
        try? store.save(session)
        self.session = session
    }

    func logout() {
        try? store.clear()
        session = nil
    }

    /// Sections allowed by the current token's scopes (Profile always shown).
    var sections: [AdminSection] {
        guard let session else { return [] }
        return AdminSection.allCases.filter { $0.scopeResource == nil || session.hasScope($0.scopeResource!) }
    }
}

struct RootView: View {
    @Bindable var model: AppModel
    var body: some View {
        if model.session == nil {
            LoginView(model: model)
        } else {
            AdminShell(model: model)
        }
    }
}
```

- [ ] **Step 4: Create the adaptive shell**

Create `eSimplifiedAdmin/AdminShell.swift`:

```swift
import SwiftUI
import EsimplifiedKit

enum AdminSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard, orders, customers, search, inventory, agentOrder, agentApprovals, profile
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .orders: "Order History"
        case .customers: "Customers"
        case .search: "Search"
        case .inventory: "Inventory"
        case .agentOrder: "Agent Order"
        case .agentApprovals: "Agent Approvals"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "chart.bar"
        case .orders: "list.bullet.rectangle"
        case .customers: "person.2"
        case .search: "magnifyingglass"
        case .inventory: "shippingbox"
        case .agentOrder: "cart.badge.plus"
        case .agentApprovals: "checkmark.seal"
        case .profile: "person.crop.circle"
        }
    }

    /// Backend scope resource gating this section; nil = always shown.
    var scopeResource: String? {
        switch self {
        case .dashboard: "statistics"
        case .orders: "order"
        case .customers: "customer"
        case .search: "search"
        case .inventory: "inventory"
        case .agentOrder: "agent_order"
        case .agentApprovals: "agent_approval"
        case .profile: nil
        }
    }
}

struct AdminShell: View {
    @Bindable var model: AppModel
    @State private var selection: AdminSection?
    @State private var showSetup2FA = false

    var body: some View {
        NavigationSplitView {
            List(model.sections, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage).tag(section)
            }
            .navigationTitle("eSimplified")
            .toolbar {
                Button("Log out") { model.logout() }
            }
        } detail: {
            if let selection {
                if selection == .profile {
                    ProfilePlaceholder(model: model, showSetup2FA: $showSetup2FA)
                } else {
                    PlaceholderDetail(title: selection.title)
                }
            } else {
                PlaceholderDetail(title: "Select a section")
            }
        }
        .sheet(isPresented: $showSetup2FA) {
            if let session = model.session {
                TwoFactorSetupView(host: session.host, accessToken: session.accessToken)
            }
        }
        .onAppear { if selection == nil { selection = model.sections.first } }
    }
}

private struct PlaceholderDetail: View {
    let title: String
    var body: some View {
        ContentUnavailableView(title, systemImage: "square.dashed",
                               description: Text("Coming in a later slice."))
            .navigationTitle(title)
    }
}

private struct ProfilePlaceholder: View {
    @Bindable var model: AppModel
    @Binding var showSetup2FA: Bool
    var body: some View {
        Form {
            if let s = model.session {
                LabeledContent("Host", value: s.host)
                LabeledContent("Account", value: s.accountType)
            }
            Button("Set up two-factor authentication") { showSetup2FA = true }
        }
        .navigationTitle("Profile")
    }
}
```

- [ ] **Step 5: Build for macOS**

Run: `cd ~/xcode/eSimPulse && xcodebuild -project Esimplified.xcodeproj -scheme eSimplifiedAdmin -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`
Expected: `BUILD SUCCEEDED`.

> `LoginView` and `TwoFactorSetupView` are referenced here but created in Tasks 6–7. To keep this task independently buildable, also create minimal stubs for them in this task (a `LoginView` with the fields and a `TwoFactorSetupView` that shows "TODO"), then flesh them out in Tasks 6–7. Concretely: in Step 4 add stub files `LoginView.swift` and `TwoFactorSetupView.swift` containing the struct signatures used above (`LoginView(model:)`, `TwoFactorSetupView(host:accessToken:)`) returning a `Text("…")`. Tasks 6–7 replace their bodies.

- [ ] **Step 6: Build for iOS Simulator**

Run: `cd ~/xcode/eSimPulse && xcodebuild -project Esimplified.xcodeproj -scheme eSimplifiedAdmin -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
cd ~/xcode/eSimPulse && git add -A && \
  git commit -m "feat: eSimplifiedAdmin app target + adaptive scope-gated shell"
```

---

### Task 6: Login screen (password + TOTP challenge)

**Files:**
- Modify: `eSimplifiedAdmin/LoginView.swift` (replace the Task 5 stub)

**Interfaces:**
- Consumes: `AppModel`, `LiveAuthClient`, `AuthResult`, `Session` (Tasks 1, 3, 5).

- [ ] **Step 1: Implement the login view**

Replace `eSimplifiedAdmin/LoginView.swift` with:

```swift
import SwiftUI
import EsimplifiedKit

struct LoginView: View {
    @Bindable var model: AppModel

    @State private var host = "https://live.esimplified.io"
    @State private var username = ""
    @State private var password = ""
    @State private var twoFAToken: String?
    @State private var code = ""
    @State private var rememberDevice = true
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        Form {
            if twoFAToken == nil {
                Section("Sign in") {
                    TextField("Host", text: $host)
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        #endif
                    TextField("Username", text: $username)
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        #endif
                    SecureField("Password", text: $password)
                    Button("Sign in") { Task { await signIn() } }
                        .disabled(busy || host.isEmpty || username.isEmpty || password.isEmpty)
                }
            } else {
                Section("Two-factor code") {
                    TextField("6-digit code", text: $code)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Toggle("Remember this device", isOn: $rememberDevice)
                    Button("Verify") { Task { await verify() } }
                        .disabled(busy || code.count < 6)
                    Button("Cancel") { twoFAToken = nil; code = "" }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .frame(maxWidth: 420)
        .navigationTitle("eSimplified Admin")
    }

    private func signIn() async {
        busy = true; defer { busy = false }; error = nil
        do {
            let trusted = try? model.store.trustedDeviceToken(host: host)
            let result = try await model.authClient().login(username: username, password: password,
                                                            host: host, trustedDeviceToken: trusted)
            switch result {
            case let .session(s): finish(s)
            case let .needs2FA(token): twoFAToken = token
            }
        } catch { self.error = "Sign-in failed. Check your details and try again." }
    }

    private func verify() async {
        guard let token = twoFAToken else { return }
        busy = true; defer { busy = false }; error = nil
        do {
            let (s, td) = try await model.authClient().verify2FA(host: host, twoFAToken: token,
                                                                 code: code, rememberDevice: rememberDevice)
            if rememberDevice, let td { try? model.store.saveTrustedDeviceToken(td, host: host) }
            finish(s)
        } catch { self.error = "That code didn't work. Try again." }
    }

    private func finish(_ session: Session) {
        guard session.accountType == "human" else {
            error = "This account can't sign in here."; return
        }
        model.adopt(session)
    }
}
```

- [ ] **Step 2: Build for macOS**

Run: `cd ~/xcode/eSimPulse && xcodebuild -project Esimplified.xcodeproj -scheme eSimplifiedAdmin -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
cd ~/xcode/eSimPulse && git add -A && \
  git commit -m "feat: login screen with TOTP 2FA challenge"
```

---

### Task 7: 2FA enrollment screen (QR + secret + verify)

**Files:**
- Modify: `eSimplifiedAdmin/TwoFactorSetupView.swift` (replace the Task 5 stub)

**Interfaces:**
- Consumes: `LiveTwoFactorClient`, `TOTPSetup`, `APIError` (Task 4).

- [ ] **Step 1: Implement the enrollment view (QR via CoreImage)**

Replace `eSimplifiedAdmin/TwoFactorSetupView.swift` with:

```swift
import SwiftUI
import CoreImage.CIFilterBuiltins
import EsimplifiedKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct TwoFactorSetupView: View {
    let host: String
    let accessToken: String
    @Environment(\.dismiss) private var dismiss

    @State private var setup: TOTPSetup?
    @State private var code = ""
    @State private var status: String?
    @State private var busy = false

    private var client: LiveTwoFactorClient { LiveTwoFactorClient(host: host, accessToken: accessToken) }

    var body: some View {
        VStack(spacing: 16) {
            Text("Set up two-factor authentication").font(.headline)
            if let setup {
                if let img = Self.qrImage(from: setup.otpauthURL) {
                    img.resizable().interpolation(.none).frame(width: 180, height: 180)
                }
                if let secret = setup.secret ?? Self.secret(from: setup.otpauthURL) {
                    Text("Secret: \(secret)").font(.caption).textSelection(.enabled)
                }
                Text("Scan the QR in your authenticator app, then enter the 6-digit code.")
                    .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
                TextField("6-digit code", text: $code)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .frame(maxWidth: 160)
                Button("Enable") { Task { await verify() } }.disabled(busy || code.count < 6)
            } else {
                ProgressView().task { await begin() }
            }
            if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            Button("Close") { dismiss() }
        }
        .padding()
        .frame(minWidth: 280)
    }

    private func begin() async {
        busy = true; defer { busy = false }
        do { setup = try await client.beginSetup() }
        catch { status = "Couldn't start setup." }
    }

    private func verify() async {
        busy = true; defer { busy = false }
        do { try await client.verify(code: code); status = "Two-factor enabled."; dismiss() }
        catch { status = "That code didn't work." }
    }

    // MARK: - QR rendering (no third-party dependency)

    private static func qrImage(from string: String) -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        #if os(macOS)
        return Image(nsImage: NSImage(cgImage: cg, size: .zero))
        #else
        return Image(uiImage: UIImage(cgImage: cg))
        #endif
    }

    private static func secret(from otpauth: String) -> String? {
        URLComponents(string: otpauth)?.queryItems?.first(where: { $0.name == "secret" })?.value
    }
}
```

- [ ] **Step 2: Build for macOS and iOS Simulator**

Run: `cd ~/xcode/eSimPulse && xcodebuild -project Esimplified.xcodeproj -scheme eSimplifiedAdmin -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`
Then: `... -destination 'generic/platform=iOS Simulator' ...`
Expected: `BUILD SUCCEEDED` for both.

- [ ] **Step 3: Manual verification (record results)**

Run the macOS app (signed, from Xcode) and confirm:
1. Login form appears; signing in with valid staff credentials lands on the shell.
2. The sidebar shows only scope-permitted sections.
3. A 2FA-required account prompts for a code and signs in on a valid TOTP.
4. Profile → "Set up two-factor authentication" shows a QR + secret; entering a valid code reports enabled.
5. Log out returns to the login screen; relaunch stays logged in (Keychain) until logout.

- [ ] **Step 4: Commit**

```bash
cd ~/xcode/eSimPulse && git add -A && \
  git commit -m "feat: TOTP 2FA enrollment screen with native QR"
```

---

## Self-Review

- **Spec coverage:** API client (Task 2) ✓; OAuth2 password grant + refresh (Task 3) ✓; 2FA login challenge (Tasks 3, 6) ✓; TOTP enrollment status/setup/verify/disable (Tasks 4, 7) ✓; session Keychain storage + trusted-device token (Task 1) ✓; adaptive shell + scope-gated sections (Task 5) ✓; multiplatform macOS+iOS (Task 5) ✓; QR via CoreImage, no deps (Task 7) ✓; client creds injected not hardcoded (Tasks 3, 5) ✓. Passkeys explicitly deferred per spec. Individual screens (Dashboard, Orders, etc.) are later slices, not this plan.
- **Placeholder scan:** UI placeholder destinations are intentional (later slices) and labeled; no TBD/TODO in code except the Task 5 stub bodies, which Tasks 6–7 replace. Removed the stray `_ = extra` lines noted in Task 3 before committing.
- **Type consistency:** `Session`, `SessionStore`, `AuthResult`, `APIError`, `LiveAPIClient`, `LiveAuthClient`, `LiveTwoFactorClient`, `TOTPSetup`, `AppModel`, `AdminSection` used identically across tasks.

## Out of Scope (future slices)

- The individual screens (Dashboard, Order History, Customers, Search, Inventory, Agent Order, Agent Approvals, Profile content beyond 2FA) — each its own spec → plan.
- WebAuthn/passkey 2FA; forgot-password; multi-account switching.
