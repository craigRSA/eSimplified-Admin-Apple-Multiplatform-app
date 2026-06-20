# Biometric Sign-in + Token Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the OAuth session alive via refresh-on-use, and add an opt-in iOS biometric ("Face ID") gate on every app open while refresh runs independently underneath.

**Architecture:** A new `SessionManager` actor in `EsimplifiedKit` becomes the single source of valid access tokens: it checks `expiresAt` before each request, refreshes within a 60s buffer (single-flight coalesced, refresh-token carry-forward), and also refreshes once on a 401 (clock-skew defense). `LiveAPIClient`/`LiveTwoFactorClient` call it on every request via an injected `AccessTokenProviding`. On iOS an `@Observable AppLockController` gates the UI behind `LAContext.evaluatePolicy` on launch and on foreground-after-grace; the token stays in a normally-accessible Keychain item so the widget/background refresh keep working. A single "Biometric sign-in" flag controls both whether iOS refreshes and whether the gate is shown.

**Tech Stack:** Swift 5.9+, SwiftUI, LocalAuthentication, Security (Keychain), Swift Concurrency (actors), XCTest. No third-party dependencies.

## Global Constraints

- **Platform floor:** Admin target iOS 26 / macOS 26; widget target iOS 17 / macOS 14; `EsimplifiedKit` `.iOS(.v17)` / `.macOS(.v14)`. Swift 5.9+.
- **No third-party dependencies** — Foundation / SwiftUI / AppKit / Charts / AppIntents / LocalAuthentication / Security / XCTest only.
- **Money is always `Decimal`** (not relevant to most tasks here, but never introduce `Double` for money).
- **Auth lives in the Keychain**, never `UserDefaults`. App ↔ widget share via the access group `$(AppIdentifierPrefix)io.esimplified.admin.shared` (already in both entitlements — do not change).
- **Trailing slashes matter:** always hit canonical `/…/` paths (e.g. `/auth/token/`). Don't change existing paths.
- **The OAuth refresh request format is already correct** (`client_id`/`client_secret` in the form body, no Basic auth — matches `admin_front_end/src/lib/utils/auth.ts`). Do NOT change `LiveAuthClient.refresh`'s request shape.
- **The user's password may have a leading space — never trim it.** (Login flow only; unchanged here.)
- **`project.pbxproj` is hand-authored** (no Xcode GUI). UUID prefixes: A0=project, A2=widget, A3=admin app. Adding a file to a target = 4 edits (PBXBuildFile, PBXFileReference, group children, Sources phase). Files added to the `EsimplifiedKit` SPM package need NO pbxproj edits.
- **Commit per task** with the trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. **Never `git push`** (denied) and never push without explicit ask.
- **Verification commands:**
  - Kit unit tests: `cd EsimplifiedKit && swift test`
  - Kit build: `cd EsimplifiedKit && swift build`
  - App build (Mac): `xcodebuild -project Esimplified.xcodeproj -scheme EsimplifiedAdmin -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`
  - App build (iOS): `xcodebuild -project Esimplified.xcodeproj -scheme EsimplifiedAdmin -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`

## File Structure

**Created:**
- `EsimplifiedKit/Sources/EsimplifiedKit/AccessTokenProviding.swift` — the token-provider protocol + `StaticTokenProvider`.
- `EsimplifiedKit/Sources/EsimplifiedKit/SessionManager.swift` — the refresh-on-use actor.
- `EsimplifiedKit/Sources/EsimplifiedKit/BiometricGate.swift` — pure `shouldRelock` decision.
- `EsimplifiedKit/Tests/EsimplifiedKitTests/SessionManagerTests.swift`
- `EsimplifiedKit/Tests/EsimplifiedKitTests/BiometricGateTests.swift`
- `EsimplifiedKit/Tests/EsimplifiedKitTests/APIClientRefreshTests.swift`
- `EsimplifiedAdmin/BiometricLock.swift` — iOS-only: `AppLockController`, `LockScreen`, privacy cover, `LAContext` authenticator, scene-phase container. (Added to app target via pbxproj.)

**Modified:**
- `EsimplifiedKit/Sources/EsimplifiedKit/Session.swift` — add biometric-flag methods to `SessionStore` + `InMemorySessionStore`.
- `EsimplifiedKit/Sources/EsimplifiedKit/KeychainSessionStore.swift` — accessibility attribute + biometric-flag item.
- `EsimplifiedKit/Sources/EsimplifiedKit/APIClient.swift` — provider-backed `LiveAPIClient` + 401 retry.
- `EsimplifiedKit/Sources/EsimplifiedKit/TwoFactorClient.swift` — provider-backed init.
- `EsimplifiedKit/Tests/EsimplifiedKitTests/SessionStoreTests.swift` — biometric-flag test.
- `EsimplifiedAdmin/EsimplifiedAdminApp.swift` — `AdminAppModel` owns `SessionManager`; bridge; `apiClient()`; env injection; remove `refreshSessionIfNeeded`; iOS scene-phase + lock gating.
- `EsimplifiedAdmin/AdminShell.swift` — drop `refreshSessionIfNeeded` from `.task`.
- `EsimplifiedAdmin/LoginView.swift` — offer biometric enrollment on iOS after sign-in.
- `EsimplifiedAdmin/ProfileScreen.swift` — biometric toggle (iOS); provider-backed clients.
- `EsimplifiedAdmin/TwoFactorSetupView.swift` — take a token provider.
- All screen files with a `LiveAPIClient(host:accessToken:)` site — migrate to the injected provider.
- `EsimplifiedAdmin/MenuBarRevenue.swift` — provider-backed (macOS).
- `EsimplifiedAdmin/AdminSiri.swift`, `EsimplifiedWidget/RevenueProvider.swift` — adopt `SessionManager`.
- `EsimplifiedAdmin/Info.plist` — `NSFaceIDUsageDescription`.
- `Esimplified.xcodeproj/project.pbxproj` — register `BiometricLock.swift` in the app target.

---

### Task 1: Keychain accessibility fix + biometric-enabled flag storage

**Files:**
- Modify: `EsimplifiedKit/Sources/EsimplifiedKit/Session.swift` (the `SessionStore` protocol + `InMemorySessionStore`)
- Modify: `EsimplifiedKit/Sources/EsimplifiedKit/KeychainSessionStore.swift`
- Test: `EsimplifiedKit/Tests/EsimplifiedKitTests/SessionStoreTests.swift`

**Interfaces:**
- Produces: `SessionStore.setBiometricEnabled(_ enabled: Bool) throws` and `SessionStore.biometricEnabled() -> Bool` (non-throwing; returns `false` on any read failure). Consumed by Tasks 6, 8, 9.

- [ ] **Step 1: Write the failing test** — append to `SessionStoreTests.swift`:

```swift
func test_inMemory_biometricEnabled_defaultsFalse_andRoundTrips() throws {
    let store = InMemorySessionStore()
    XCTAssertFalse(store.biometricEnabled())
    try store.setBiometricEnabled(true)
    XCTAssertTrue(store.biometricEnabled())
    try store.setBiometricEnabled(false)
    XCTAssertFalse(store.biometricEnabled())
}
```

- [ ] **Step 2: Run it to confirm it fails to compile** — `cd EsimplifiedKit && swift test --filter SessionStoreTests` → FAIL ("value of type 'InMemorySessionStore' has no member 'biometricEnabled'").

- [ ] **Step 3: Add the protocol requirements + InMemory implementation.** In `Session.swift`, add to the `SessionStore` protocol (after `trustedDeviceToken`):

```swift
    func setBiometricEnabled(_ enabled: Bool) throws
    func biometricEnabled() -> Bool
```

In `InMemorySessionStore`, add a stored property and the two methods:

```swift
    private var biometric = false

    public func setBiometricEnabled(_ enabled: Bool) throws { biometric = enabled }
    public func biometricEnabled() -> Bool { biometric }
```

- [ ] **Step 4: Implement in `KeychainSessionStore`.** Add a biometric-flag account, the two methods, and set the accessibility attribute on every write. In `KeychainSessionStore.swift`:

Add next to `sessionAccount`:
```swift
    private let biometricAccount = "biometric-enabled"
```

Add the two methods (before the `private func write`):
```swift
    public func setBiometricEnabled(_ enabled: Bool) throws {
        try write(Data([enabled ? 1 : 0]), account: biometricAccount)
    }

    public func biometricEnabled() -> Bool {
        (try? read(account: biometricAccount))??.first == 1
    }
```

Update `write(_:account:)` to set the accessibility class (so the widget/background can read after first unlock, and the item never syncs to iCloud/backups):
```swift
    private func write(_ data: Data, account: String) throws {
        try delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }
```

- [ ] **Step 5: Run the test** — `cd EsimplifiedKit && swift test --filter SessionStoreTests` → PASS. Then `swift build` to confirm the keychain store still compiles.

- [ ] **Step 6: Commit**

```bash
git add EsimplifiedKit/Sources/EsimplifiedKit/Session.swift EsimplifiedKit/Sources/EsimplifiedKit/KeychainSessionStore.swift EsimplifiedKit/Tests/EsimplifiedKitTests/SessionStoreTests.swift
git commit -m "feat(kit): keychain AfterFirstUnlock accessibility + biometric-enabled flag

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `AccessTokenProviding` protocol + `StaticTokenProvider`

**Files:**
- Create: `EsimplifiedKit/Sources/EsimplifiedKit/AccessTokenProviding.swift`
- Test: `EsimplifiedKit/Tests/EsimplifiedKitTests/APIClientRefreshTests.swift` (created here, extended in Task 4)

**Interfaces:**
- Produces:
  - `protocol AccessTokenProviding: Sendable { func validAccessToken() async throws -> String; func refreshedAccessToken(after staleToken: String) async throws -> String }`
  - `struct StaticTokenProvider: AccessTokenProviding` — returns a fixed token; throws `APIError.authExpired` from `validAccessToken()` when empty, and always from `refreshedAccessToken(after:)` (a static token cannot refresh). Consumed by Tasks 3, 4, 6, 7, 10.

- [ ] **Step 1: Write the failing test** — create `APIClientRefreshTests.swift`:

```swift
import XCTest
@testable import EsimplifiedKit

final class APIClientRefreshTests: XCTestCase {
    func test_staticProvider_returnsToken_andCannotRefresh() async throws {
        let p = StaticTokenProvider("tok-1")
        let v = try await p.validAccessToken()
        XCTAssertEqual(v, "tok-1")
        do { _ = try await p.refreshedAccessToken(after: "tok-1"); XCTFail("expected authExpired") }
        catch { XCTAssertEqual(error as? APIError, .authExpired) }
    }

    func test_staticProvider_emptyToken_throwsAuthExpired() async {
        let p = StaticTokenProvider("")
        do { _ = try await p.validAccessToken(); XCTFail("expected authExpired") }
        catch { XCTAssertEqual(error as? APIError, .authExpired) }
    }
}
```

- [ ] **Step 2: Run it to confirm it fails** — `cd EsimplifiedKit && swift test --filter APIClientRefreshTests` → FAIL ("cannot find 'StaticTokenProvider'").

- [ ] **Step 3: Create `AccessTokenProviding.swift`:**

```swift
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
```

- [ ] **Step 4: Run the test** — `cd EsimplifiedKit && swift test --filter APIClientRefreshTests` → PASS.

- [ ] **Step 5: Commit**

```bash
git add EsimplifiedKit/Sources/EsimplifiedKit/AccessTokenProviding.swift EsimplifiedKit/Tests/EsimplifiedKitTests/APIClientRefreshTests.swift
git commit -m "feat(kit): AccessTokenProviding protocol + StaticTokenProvider

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `SessionManager` actor — refresh-on-use core

**Files:**
- Create: `EsimplifiedKit/Sources/EsimplifiedKit/SessionManager.swift`
- Test: `EsimplifiedKit/Tests/EsimplifiedKitTests/SessionManagerTests.swift`

**Interfaces:**
- Consumes: `Session`, `SessionStore`, `AuthClient`, `APIError`, `AccessTokenProviding` (Tasks prior).
- Produces:
  - `actor SessionManager: AccessTokenProviding`
  - `init(session: Session?, store: SessionStore, authClient: AuthClient, refreshBufferSeconds: TimeInterval = 60, refreshEnabled: Bool = true, now: @escaping @Sendable () -> Date = { Date() }, onChange: @escaping @Sendable (Session?) -> Void = { _ in })`
  - `func currentSession() -> Session?`
  - `func validAccessToken() async throws -> String`
  - `func refreshedAccessToken(after staleToken: String) async throws -> String` (the 401 path; implemented here — Task 4 only wires the client to call it)
  - `func adopt(_ session: Session)`
  - `func clear()`
  - `func setRefreshEnabled(_ enabled: Bool)`
- Notes for consumers: `onChange` fires on **adopt**, **clear**, and **invalidation** (→ `nil`), NOT on a silent token refresh (so the UI doesn't churn). The manager persists every new session to `store` itself. `now` is injectable for deterministic tests.

- [ ] **Step 1: Write the failing tests** — create `SessionManagerTests.swift` with a fake auth client and the core behaviors:

```swift
import XCTest
@testable import EsimplifiedKit

private actor CallCounter { var count = 0; func bump() -> Int { count += 1; return count } }

/// Fake refresh: each call returns a session whose access token encodes the call
/// index, with a fresh +3600s expiry. `refreshReturnsEmptyRefreshToken` simulates
/// a server that omits a rotated refresh_token.
private final class FakeAuthClient: AuthClient, @unchecked Sendable {
    let counter = CallCounter()
    var refreshReturnsEmptyRefreshToken = false
    var refreshError: Error?
    private(set) var lastRefreshToken: String?

    func login(username: String, password: String, host: String, trustedDeviceToken: String?) async throws -> AuthResult { .needs2FA(token: "x") }
    func verify2FA(host: String, twoFAToken: String, code: String, rememberDevice: Bool) async throws -> (Session, trustedDeviceToken: String?) { throw APIError.decoding }

    func refresh(host: String, refreshToken: String) async throws -> Session {
        lastRefreshToken = refreshToken
        if let refreshError { throw refreshError }
        let n = await counter.bump()
        return Session(host: host, accessToken: "acc-\(n)",
                       refreshToken: refreshReturnsEmptyRefreshToken ? "" : "ref-\(n)",
                       expiresAt: Date(timeIntervalSinceNow: 3600),
                       scopes: ["statistics:read"], accountType: "human")
    }
}

final class SessionManagerTests: XCTestCase {
    private func session(access: String, refresh: String, expiresIn: TimeInterval) -> Session {
        Session(host: "https://h", accessToken: access, refreshToken: refresh,
                expiresAt: Date(timeIntervalSinceNow: expiresIn),
                scopes: ["statistics:read"], accountType: "human")
    }

    func test_validAccessToken_returnsCurrent_whenFarFromExpiry() async throws {
        let auth = FakeAuthClient()
        let mgr = SessionManager(session: session(access: "acc-0", refresh: "ref-0", expiresIn: 1000),
                                 store: InMemorySessionStore(), authClient: auth)
        let token = try await mgr.validAccessToken()
        XCTAssertEqual(token, "acc-0")
        let calls = await auth.counter.count
        XCTAssertEqual(calls, 0, "must not refresh when far from expiry")
    }

    func test_validAccessToken_refreshes_whenWithinBuffer() async throws {
        let auth = FakeAuthClient()
        let store = InMemorySessionStore()
        let mgr = SessionManager(session: session(access: "acc-0", refresh: "ref-0", expiresIn: 30),
                                 store: store, authClient: auth, refreshBufferSeconds: 60)
        let token = try await mgr.validAccessToken()
        XCTAssertEqual(token, "acc-1")
        XCTAssertEqual(try store.load()?.accessToken, "acc-1", "refreshed session is persisted")
    }

    func test_validAccessToken_throwsAuthExpired_whenRefreshDisabledAndExpired() async {
        let auth = FakeAuthClient()
        let store = InMemorySessionStore()
        let mgr = SessionManager(session: session(access: "acc-0", refresh: "ref-0", expiresIn: -10),
                                 store: store, authClient: auth, refreshEnabled: false)
        do { _ = try await mgr.validAccessToken(); XCTFail("expected authExpired") }
        catch { XCTAssertEqual(error as? APIError, .authExpired) }
        let calls = await auth.counter.count
        XCTAssertEqual(calls, 0)
        XCTAssertNil(await mgr.currentSession(), "expired + no-refresh clears the session")
    }

    func test_refresh_carriesForwardOldRefreshToken_whenResponseOmitsOne() async throws {
        let auth = FakeAuthClient(); auth.refreshReturnsEmptyRefreshToken = true
        let mgr = SessionManager(session: session(access: "acc-0", refresh: "ref-0", expiresIn: 0),
                                 store: InMemorySessionStore(), authClient: auth)
        _ = try await mgr.validAccessToken()
        XCTAssertEqual(await mgr.currentSession()?.refreshToken, "ref-0",
                       "an omitted refresh_token must not blank the existing one")
    }

    func test_concurrentValidAccessToken_coalescesIntoOneRefresh() async throws {
        let auth = FakeAuthClient()
        let mgr = SessionManager(session: session(access: "acc-0", refresh: "ref-0", expiresIn: 0),
                                 store: InMemorySessionStore(), authClient: auth)
        async let a = mgr.validAccessToken()
        async let b = mgr.validAccessToken()
        async let c = mgr.validAccessToken()
        let results = try await [a, b, c]
        let calls = await auth.counter.count
        XCTAssertEqual(calls, 1, "concurrent callers share one in-flight refresh")
        XCTAssertEqual(Set(results), ["acc-1"])
    }
}
```

- [ ] **Step 2: Run to confirm failure** — `cd EsimplifiedKit && swift test --filter SessionManagerTests` → FAIL ("cannot find 'SessionManager'").

- [ ] **Step 3: Implement `SessionManager.swift`:**

```swift
import Foundation

/// Single source of valid access tokens. Checks `expiresAt` before each request
/// and refreshes within `refreshBufferSeconds`; coalesces concurrent refreshes
/// into one in-flight Task; carries the old refresh token forward when the server
/// omits a rotated one; persists every new session. Refresh is gated by
/// `refreshEnabled` (the app sets this from the biometric/platform policy).
public actor SessionManager: AccessTokenProviding {
    private var session: Session?
    private let store: SessionStore
    private let authClient: AuthClient
    private let refreshBuffer: TimeInterval
    private var refreshEnabled: Bool
    private let now: @Sendable () -> Date
    private let onChange: @Sendable (Session?) -> Void

    private var refreshTask: Task<Session, Error>?

    public init(session: Session?, store: SessionStore, authClient: AuthClient,
                refreshBufferSeconds: TimeInterval = 60, refreshEnabled: Bool = true,
                now: @escaping @Sendable () -> Date = { Date() },
                onChange: @escaping @Sendable (Session?) -> Void = { _ in }) {
        self.session = session
        self.store = store
        self.authClient = authClient
        self.refreshBuffer = refreshBufferSeconds
        self.refreshEnabled = refreshEnabled
        self.now = now
        self.onChange = onChange
    }

    public func currentSession() -> Session? { session }

    public func setRefreshEnabled(_ enabled: Bool) { refreshEnabled = enabled }

    public func adopt(_ session: Session) {
        self.session = session
        try? store.save(session)
        onChange(session)
    }

    public func clear() {
        session = nil
        refreshTask?.cancel(); refreshTask = nil
        try? store.clear()
        onChange(nil)
    }

    public func validAccessToken() async throws -> String {
        guard let current = session else { throw APIError.authExpired }
        if current.expiresAt.timeIntervalSince(now()) > refreshBuffer {
            return current.accessToken
        }
        return try await performRefresh(current).accessToken
    }

    public func refreshedAccessToken(after staleToken: String) async throws -> String {
        guard let current = session else { throw APIError.authExpired }
        // Another caller already rotated past the token that 401'd — use the new one.
        if current.accessToken != staleToken { return current.accessToken }
        return try await performRefresh(current).accessToken
    }

    /// Coalesced, policy-gated refresh. Concurrent callers await the same Task.
    private func performRefresh(_ current: Session) async throws -> Session {
        if let inFlight = refreshTask { return try await inFlight.value }
        guard refreshEnabled else {
            // Expired and not allowed to refresh → invalidate and sign out.
            invalidate()
            throw APIError.authExpired
        }
        let host = current.host
        let oldRefresh = current.refreshToken
        let task = Task { () throws -> Session in
            let refreshed = try await authClient.refresh(host: host, refreshToken: oldRefresh)
            // Carry forward the old refresh token if the server omitted a new one.
            return refreshed.refreshToken.isEmpty
                ? Session(host: refreshed.host, accessToken: refreshed.accessToken,
                          refreshToken: oldRefresh, expiresAt: refreshed.expiresAt,
                          scopes: refreshed.scopes, accountType: refreshed.accountType)
                : refreshed
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let newSession = try await task.value
            session = newSession
            try? store.save(newSession)   // silent refresh: persist, no onChange
            return newSession
        } catch let error as APIError where error == .authExpired {
            invalidate()                  // refresh token revoked/expired
            throw error
        }
        // Any other error (e.g. .unreachable) propagates WITHOUT clearing the
        // session — it's transient; the next request retries.
    }

    private func invalidate() {
        session = nil
        try? store.clear()
        onChange(nil)
    }
}
```

- [ ] **Step 4: Run the tests** — `cd EsimplifiedKit && swift test --filter SessionManagerTests` → all PASS.

- [ ] **Step 5: Commit**

```bash
git add EsimplifiedKit/Sources/EsimplifiedKit/SessionManager.swift EsimplifiedKit/Tests/EsimplifiedKitTests/SessionManagerTests.swift
git commit -m "feat(kit): SessionManager actor — refresh-on-use, coalesced, carry-forward

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Provider-backed `LiveAPIClient` (+ 401 retry) and `LiveTwoFactorClient`

**Files:**
- Modify: `EsimplifiedKit/Sources/EsimplifiedKit/APIClient.swift`
- Modify: `EsimplifiedKit/Sources/EsimplifiedKit/TwoFactorClient.swift`
- Test: `EsimplifiedKit/Tests/EsimplifiedKitTests/APIClientRefreshTests.swift` (extend)

**Interfaces:**
- Consumes: `AccessTokenProviding`, `StaticTokenProvider`, `MockURLProtocol` (existing test helper).
- Produces:
  - `LiveAPIClient.init(host:tokenProvider:session:)` (new primary init) and a `convenience init(host:accessToken:session:)` preserving the old signature.
  - `LiveTwoFactorClient.init(host:tokenProvider:session:)` + preserved `convenience init(host:accessToken:session:)`.
- Behavior: `get` fetches a token via `validAccessToken()`, sends the request, and on a 401 calls `refreshedAccessToken(after:)` and retries **once**; a second 401 throws `authExpired`.

- [ ] **Step 1: Write the failing tests** — append to `APIClientRefreshTests.swift`. (Uses the repo's existing `MockURLProtocol`; check `MockURLProtocol.swift` for its exact request-handler API and mirror the pattern used in `APIClientTests.swift`.)

```swift
    /// Provider that serves one stale token, then a refreshed one after a 401.
    private actor SequenceProvider: AccessTokenProviding {
        private var refreshed = false
        func validAccessToken() async throws -> String { "stale" }
        func refreshedAccessToken(after staleToken: String) async throws -> String {
            refreshed = true; return "fresh"
        }
    }

    func test_get_retriesOnceAfter401_withRefreshedToken() async throws {
        // First response 401, second 200 — assert the retry carries "Bearer fresh".
        var seenAuthHeaders: [String] = []
        MockURLProtocol.requestHandler = { request in
            seenAuthHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
            let code = seenAuthHeaders.count == 1 ? 401 : 200
            let body = code == 200 ? Data(#"{"ok":true}"#.utf8) : Data()
            let resp = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = LiveAPIClient(host: "https://h", tokenProvider: SequenceProvider(),
                                   session: URLSession(configuration: config))
        struct OK: Decodable { let ok: Bool }
        let result = try await client.get("/api/x/", query: [:], as: OK.self)
        XCTAssertTrue(result.ok)
        XCTAssertEqual(seenAuthHeaders, ["Bearer stale", "Bearer fresh"])
    }

    func test_get_throwsAuthExpired_whenRetryAlso401() async {
        MockURLProtocol.requestHandler = { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = LiveAPIClient(host: "https://h", tokenProvider: SequenceProvider(),
                                   session: URLSession(configuration: config))
        struct OK: Decodable { let ok: Bool }
        do { _ = try await client.get("/api/x/", query: [:], as: OK.self); XCTFail("expected authExpired") }
        catch { XCTAssertEqual(error as? APIError, .authExpired) }
    }
```

- [ ] **Step 2: Run to confirm failure** — `cd EsimplifiedKit && swift test --filter APIClientRefreshTests` → FAIL ("extra argument 'tokenProvider'").

- [ ] **Step 3: Refactor `LiveAPIClient`** in `APIClient.swift` to hold a provider and retry once on 401:

```swift
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
            components.queryItems = query.sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
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
            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = (body?.isEmpty == false) ? String(body!.prefix(300)) : nil
            throw APIError.requestFailed(status: http.statusCode, serverMessage: message)
        }
    }
}
```

- [ ] **Step 4: Add a provider-backed init to `LiveTwoFactorClient`** in `TwoFactorClient.swift`. It must use a fresh token per request, so store the provider and resolve the token inside `send`. Replace the stored `accessToken` with a provider:

  - Change the stored property `private let accessToken: String` → `private let tokenProvider: AccessTokenProviding`.
  - Replace the init with:
    ```swift
    public init(host: String, tokenProvider: AccessTokenProviding, session: URLSession = .shared) {
        self.host = host
        self.tokenProvider = tokenProvider
        self.session = session
    }
    public convenience init(host: String, accessToken: String, session: URLSession = .shared) {
        self.init(host: host, tokenProvider: StaticTokenProvider(accessToken), session: session)
    }
    ```
  - In `send(_:_:json:)`, replace the line that sets the bearer header. Find:
    ```swift
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    ```
    and change the method to resolve the token first (insert at the top of `send`, before building the request):
    ```swift
    let token = try await tokenProvider.validAccessToken()
    ```
    then use `request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")`.
  - (2FA endpoints don't need the 401-retry; `validAccessToken()` alone is sufficient and keeps this change minimal.)

- [ ] **Step 5: Run the full kit suite** — `cd EsimplifiedKit && swift test` → all PASS (existing `APIClientTests` and `TwoFactorClientTests` still pass via the preserved convenience inits).

- [ ] **Step 6: Commit**

```bash
git add EsimplifiedKit/Sources/EsimplifiedKit/APIClient.swift EsimplifiedKit/Sources/EsimplifiedKit/TwoFactorClient.swift EsimplifiedKit/Tests/EsimplifiedKitTests/APIClientRefreshTests.swift
git commit -m "feat(kit): provider-backed API clients with 401 refresh-and-retry

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: `BiometricGate.shouldRelock` pure decision

**Files:**
- Create: `EsimplifiedKit/Sources/EsimplifiedKit/BiometricGate.swift`
- Test: `EsimplifiedKit/Tests/EsimplifiedKitTests/BiometricGateTests.swift`

**Interfaces:**
- Produces: `enum BiometricGate { static func shouldRelock(backgroundedAt: Date?, now: Date, grace: TimeInterval) -> Bool }`. Consumed by Task 8.

- [ ] **Step 1: Write the failing tests** — create `BiometricGateTests.swift`:

```swift
import XCTest
@testable import EsimplifiedKit

final class BiometricGateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_750_000_000)

    func test_neverBackgrounded_doesNotRelock() {
        XCTAssertFalse(BiometricGate.shouldRelock(backgroundedAt: nil, now: t0, grace: 180))
    }
    func test_withinGrace_doesNotRelock() {
        XCTAssertFalse(BiometricGate.shouldRelock(backgroundedAt: t0, now: t0.addingTimeInterval(120), grace: 180))
    }
    func test_pastGrace_relocks() {
        XCTAssertTrue(BiometricGate.shouldRelock(backgroundedAt: t0, now: t0.addingTimeInterval(181), grace: 180))
    }
    func test_exactlyAtGrace_doesNotRelock() {
        XCTAssertFalse(BiometricGate.shouldRelock(backgroundedAt: t0, now: t0.addingTimeInterval(180), grace: 180))
    }
}
```

- [ ] **Step 2: Run to confirm failure** — `cd EsimplifiedKit && swift test --filter BiometricGateTests` → FAIL ("cannot find 'BiometricGate'").

- [ ] **Step 3: Implement `BiometricGate.swift`:**

```swift
import Foundation

/// Pure policy for the biometric app-lock: decide whether returning to the
/// foreground should re-lock, given when the app was backgrounded and the grace
/// window. Kept here (not in the app) so it has real unit tests.
public enum BiometricGate {
    public static func shouldRelock(backgroundedAt: Date?, now: Date, grace: TimeInterval) -> Bool {
        guard let backgroundedAt else { return false }
        return now.timeIntervalSince(backgroundedAt) > grace
    }
}
```

- [ ] **Step 4: Run the tests** — `cd EsimplifiedKit && swift test --filter BiometricGateTests` → all PASS.

- [ ] **Step 5: Commit**

```bash
git add EsimplifiedKit/Sources/EsimplifiedKit/BiometricGate.swift EsimplifiedKit/Tests/EsimplifiedKitTests/BiometricGateTests.swift
git commit -m "feat(kit): BiometricGate.shouldRelock pure decision

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: `AdminAppModel` owns `SessionManager`; bridge, policy, `apiClient()`; remove one-shot refresh

**Files:**
- Modify: `EsimplifiedAdmin/EsimplifiedAdminApp.swift`
- Modify: `EsimplifiedAdmin/AdminShell.swift` (drop `refreshSessionIfNeeded` from `.task`)

**Interfaces:**
- Consumes: `SessionManager`, `AccessTokenProviding`, `StaticTokenProvider`, `LiveAuthClient`, `LiveAPIClient`.
- Produces (on `AdminAppModel`):
  - `let sessionManager: SessionManager` (exposed so the app can inject it as `any AccessTokenProviding`).
  - `func apiClient() -> LiveAPIClient` (provider-backed).
  - `adopt`/`logout` delegate to the manager; `session` is set only via the manager's `onChange`.
  - `var biometricEnabled: Bool` (mirrors the store flag) and `func setBiometricEnabled(_:)`.
- This task has no unit test (app target is verified by build + run, per repo convention). Verify with both build commands.

- [ ] **Step 1: Rewrite `AdminAppModel`'s session ownership.** In `EsimplifiedAdminApp.swift`, replace the stored `private(set) var session`, `init`, `adopt`, `refreshSessionIfNeeded`, `logout`, and `loadTenants`'s client construction with the manager-backed versions:

```swift
@Observable
@MainActor
final class AdminAppModel {
    let store: SessionStore
    private(set) var session: Session?
    let sessionManager: SessionManager
    private(set) var biometricEnabled: Bool

    var selectedTenant: Tenant?
    private(set) var tenants: [Tenant] = []
    var selection: AdminSection?

    let clientID: String
    let clientSecret: String
    let host: String

    init(store: SessionStore = KeychainSessionStore()) {
        self.store = store
        let id = (Bundle.main.object(forInfoDictionaryKey: "ESPClientID") as? String) ?? ""
        let secret = (Bundle.main.object(forInfoDictionaryKey: "ESPClientSecret") as? String) ?? ""
        self.clientID = id
        self.clientSecret = secret
        let configured = (Bundle.main.object(forInfoDictionaryKey: "ESPHost") as? String) ?? ""
        self.host = configured.isEmpty ? "https://live.esimplified.io" : configured

        let loaded = try? store.load()
        self.session = loaded
        let enabled = store.biometricEnabled()
        self.biometricEnabled = enabled

        // Refresh is allowed on macOS always; on iOS only when biometric sign-in
        // is enabled (otherwise the session is ephemeral — sign out on expiry).
        #if os(macOS)
        let refreshEnabled = true
        #else
        let refreshEnabled = enabled
        #endif

        self.sessionManager = SessionManager(
            session: loaded, store: store,
            authClient: LiveAuthClient(clientID: id, clientSecret: secret),
            refreshEnabled: refreshEnabled)

        // The manager is the single writer of `session`; mirror its changes to the
        // observable on the main actor (also clears tenants on sign-out).
        let mgr = sessionManager
        Task { await mgr.setOnChange { [weak self] newSession in
            Task { @MainActor in
                self?.session = newSession
                if newSession == nil { self?.tenants = []; self?.selectedTenant = nil }
            }
        } }
    }

    func authClient() -> LiveAuthClient { LiveAuthClient(clientID: clientID, clientSecret: clientSecret) }

    func apiClient() -> LiveAPIClient { LiveAPIClient(host: host, tokenProvider: sessionManager) }

    func adopt(_ session: Session) {
        Task { await sessionManager.adopt(session) }   // persists + fires onChange → sets self.session
    }

    func logout() {
        Task { await sessionManager.clear() }            // clears store + fires onChange(nil)
    }

    func setBiometricEnabled(_ enabled: Bool) {
        biometricEnabled = enabled
        try? store.setBiometricEnabled(enabled)
        #if os(iOS)
        Task { await sessionManager.setRefreshEnabled(enabled) }
        #endif
    }

    var tenantScope: String? { selectedTenant?.schemaName }

    func loadTenants() async {
        guard let session, tenants.isEmpty else { return }
        let client = apiClient()
        if let page = try? await client.get("/api/tenants/", query: ["limit": "1000", "order_by": "name"],
                                            as: TenantsPage.self) {
            tenants = page.tenants
            if selectedTenant == nil, tenants.count == 1 { selectedTenant = tenants.first }
        }
    }

    var sections: [AdminSection] {
        guard let session else { return [] }
        return AdminSection.allCases.filter {
            $0 != .agentOrder && ($0.scopeResource == nil || session.hasScope($0.scopeResource!))
        }
    }
}
```

- [ ] **Step 2: Add the `setOnChange` setter to `SessionManager`** (the model wires its callback after init). In `SessionManager.swift`, change `onChange` from `let` to `var` and add:

```swift
    public func setOnChange(_ handler: @escaping @Sendable (Session?) -> Void) { onChange = handler }
```

Change the stored property declaration to `private var onChange: @Sendable (Session?) -> Void`.

- [ ] **Step 3: Drop the one-shot refresh from `AdminShell`.** In `AdminShell.swift`, change line 74 from:

```swift
        .task { await model.refreshSessionIfNeeded(); await model.loadTenants() }
```
to:
```swift
        .task { await model.loadTenants() }
```

- [ ] **Step 4: Build both platforms.**

```bash
xcodebuild -project Esimplified.xcodeproj -scheme EsimplifiedAdmin -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Esimplified.xcodeproj -scheme EsimplifiedAdmin -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```
Expected: both succeed. (Screens still build their own fixed-token clients — migrated in Task 7 — so behavior is unchanged except that the one-shot refresh is gone; that's fine because Task 7 lands next.)

- [ ] **Step 5: Commit**

```bash
git add EsimplifiedAdmin/EsimplifiedAdminApp.swift EsimplifiedAdmin/AdminShell.swift EsimplifiedKit/Sources/EsimplifiedKit/SessionManager.swift
git commit -m "feat(admin): AdminAppModel owns SessionManager; remove one-shot refresh

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Inject the token provider; migrate all request call sites to refresh-on-use

**Files:**
- Modify: `EsimplifiedAdmin/EsimplifiedAdminApp.swift` (add the environment key + inject at root)
- Modify each screen with a `LiveAPIClient(host:accessToken:)` site:
  `OrdersScreen.swift:88`, `AgentApprovalsScreen.swift:41`, `DashboardScreen.swift:159`,
  `SearchScreen.swift:126`, `InventoryScreen.swift:91`, `CustomersScreen.swift:98`,
  `CustomerDetailScreen.swift:40,500,548`, `ProfileScreen.swift:135`
- Modify `ProfileScreen.swift:28` + `TwoFactorSetupView.swift` (LiveTwoFactorClient → provider)
- Modify `MenuBarRevenue.swift:21` (macOS)

**Interfaces:**
- Consumes: `AccessTokenProviding`, `model.sessionManager`.
- Produces: `EnvironmentValues.tokenProvider: any AccessTokenProviding` (app target). Every screen reads it and builds clients with `tokenProvider:` instead of `accessToken:`.
- No unit test — verified by build on both platforms + manual run.

- [ ] **Step 1: Add the environment key and inject it.** In `EsimplifiedAdminApp.swift`, add (e.g. just below the imports or near `AdminRootView`):

```swift
private struct TokenProviderKey: EnvironmentKey {
    static let defaultValue: any AccessTokenProviding = StaticTokenProvider("")
}
extension EnvironmentValues {
    var tokenProvider: any AccessTokenProviding {
        get { self[TokenProviderKey.self] }
        set { self[TokenProviderKey.self] = newValue }
    }
}
```

Inject it in `AdminRootView` on the signed-in branch:
```swift
struct AdminRootView: View {
    @Bindable var model: AdminAppModel
    var body: some View {
        if model.session == nil {
            LoginView(model: model)
        } else {
            AdminShell(model: model)
                .environment(\.tokenProvider, model.sessionManager)
        }
    }
}
```
(Task 8 wraps the `AdminShell` branch with the iOS lock; keep the `.environment` on it.)

- [ ] **Step 2: Migrate each screen.** For every screen file listed, (a) add the env property to the view struct, and (b) replace the client construction. The mechanical change per file:

Add near the other `@State`/properties of the view:
```swift
    @Environment(\.tokenProvider) private var tokenProvider
```
Replace each:
```swift
LiveAPIClient(host: session.host, accessToken: session.accessToken)
```
with:
```swift
LiveAPIClient(host: session.host, tokenProvider: tokenProvider)
```

Apply to: `OrdersScreen` (line 88), `AgentApprovalsScreen` (41), `DashboardScreen` (159), `SearchScreen` (126), `InventoryScreen` (91), `CustomersScreen` (98), `CustomerDetailScreen` (the computed `client` at line 40, plus the two inline clients at 500 and 548 — all three), `ProfileScreen` (135).

> Note for `CustomerDetailScreen.swift:40`, the computed property becomes:
> ```swift
> private var client: LiveAPIClient { LiveAPIClient(host: session.host, tokenProvider: tokenProvider) }
> ```

- [ ] **Step 3: Migrate the 2FA clients.** In `ProfileScreen.swift`:
  - Line 28 computed `twoFA`:
    ```swift
    private var twoFA: LiveTwoFactorClient {
        LiveTwoFactorClient(host: session.host, tokenProvider: tokenProvider)
    }
    ```
  - Line 83 — pass the provider into the setup view:
    ```swift
    TwoFactorSetupView(host: session.host, tokenProvider: tokenProvider)
    ```
  In `TwoFactorSetupView.swift`, change the init (around lines 25-28) to take a provider:
    ```swift
    init(host: String, tokenProvider: any AccessTokenProviding) {
        // keep whatever other stored properties the initializer sets
        self.client = LiveTwoFactorClient(host: host, tokenProvider: tokenProvider)
    }
    ```
  (Read `TwoFactorSetupView.swift` first to preserve its other init assignments.)

- [ ] **Step 4: Migrate `MenuBarRevenue` (macOS).** In `EsimplifiedAdminApp.swift`, the MenuBar `.task` (lines 41-48) calls `menu.load(session: model.session)`. Pass the provider through. Change the call to:
  ```swift
  .task(id: model.session?.accessToken) {
      await menu.load(session: model.session, provider: model.sessionManager)
      while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(300))
          if Task.isCancelled { break }
          await menu.load(session: model.session, provider: model.sessionManager)
      }
  }
  ```
  In `MenuBarRevenue.swift`, change `load(session:)` to `load(session:provider:)` and build the client with the provider:
  ```swift
  func load(session: Session?, provider: any AccessTokenProviding) async {
      guard let session else { /* existing no-session handling */ return }
      let client = LiveAPIClient(host: session.host, tokenProvider: provider)
      // … rest unchanged …
  }
  ```
  (Read `MenuBarRevenue.swift:21` context first to preserve the surrounding logic and the no-session branch.)

- [ ] **Step 5: Build both platforms.**

```bash
xcodebuild -project Esimplified.xcodeproj -scheme EsimplifiedAdmin -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Esimplified.xcodeproj -scheme EsimplifiedAdmin -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```
Expected: both succeed with no `accessToken:` call sites left in the screens (verify: `grep -rn "accessToken: session.accessToken" EsimplifiedAdmin/` returns only `AdminSiri.swift`, handled in Task 10).

- [ ] **Step 6: Commit**

```bash
git add EsimplifiedAdmin/
git commit -m "feat(admin): route all requests through the refresh-on-use token provider

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: iOS biometric lock — controller, lock screen, privacy cover, scene-phase gating

**Files:**
- Create: `EsimplifiedAdmin/BiometricLock.swift`
- Modify: `Esimplified.xcodeproj/project.pbxproj` (register the new file in the app target)
- Modify: `EsimplifiedAdmin/Info.plist` (`NSFaceIDUsageDescription`)
- Modify: `EsimplifiedAdmin/EsimplifiedAdminApp.swift` (apply the lock container on iOS)

**Interfaces:**
- Consumes: `BiometricGate.shouldRelock`, `LocalAuthentication`.
- Produces: `AppLockController` (`@Observable @MainActor`), `LockScreen`, `LockContainer` view modifier, `BiometricAuthenticator` protocol + `LAContextAuthenticator`.
- Verified by build (both platforms — the file is fully `#if os(iOS)`) + manual run on an iOS Simulator/device.

- [ ] **Step 1: Create `EsimplifiedAdmin/BiometricLock.swift`** (entirely iOS-only):

```swift
#if os(iOS)
import SwiftUI
import LocalAuthentication
import EsimplifiedKit

/// Abstracts LocalAuthentication so the controller is testable and the policy
/// choice is centralized. Uses `.deviceOwnerAuthentication` (biometrics WITH
/// passcode fallback) — required so a biometric lockout can recover via passcode.
protocol BiometricAuthenticator {
    func canEvaluate() -> Bool
    func evaluate(reason: String) async -> Bool
}

struct LAContextAuthenticator: BiometricAuthenticator {
    func canEvaluate() -> Bool {
        // canEvaluatePolicy's result is volatile — checked fresh each call, never stored.
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }
    func evaluate(reason: String) async -> Bool {
        let context = LAContext()   // fresh context per evaluation
        do { return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) }
        catch { return false }
    }
}

/// Drives the iOS app-lock. Purely a UI gate — never touches the session/token,
/// so refresh keeps running underneath. `isLocked` overlays the lock screen.
@Observable
@MainActor
final class AppLockController {
    private(set) var isLocked = false
    var isInactive = false      // drives the privacy cover in the app switcher
    private var backgroundedAt: Date?
    private var authenticating = false

    private let grace: TimeInterval
    private let authenticator: BiometricAuthenticator
    /// Whether the lock is in force (biometric sign-in enabled & device capable).
    var isEnabled: () -> Bool

    init(grace: TimeInterval = 180,
         authenticator: BiometricAuthenticator = LAContextAuthenticator(),
         isEnabled: @escaping () -> Bool) {
        self.grace = grace
        self.authenticator = authenticator
        self.isEnabled = isEnabled
    }

    /// Call once when a signed-in shell first appears (cold launch).
    func lockOnLaunch() {
        guard isEnabled() else { isLocked = false; return }
        isLocked = true
    }

    func willResignActive() {
        isInactive = true
        if backgroundedAt == nil { backgroundedAt = Date() }
    }

    func didBecomeActive() {
        isInactive = false
        guard isEnabled() else { isLocked = false; backgroundedAt = nil; return }
        if BiometricGate.shouldRelock(backgroundedAt: backgroundedAt, now: Date(), grace: grace) {
            isLocked = true
        }
        backgroundedAt = nil
    }

    func authenticate() async {
        guard isLocked, !authenticating else { return }
        // If the device can't evaluate at all, don't trap the user out.
        guard authenticator.canEvaluate() else { isLocked = false; return }
        authenticating = true; defer { authenticating = false }
        if await authenticator.evaluate(reason: "Unlock eSimplified Admin") {
            isLocked = false
        }
    }
}

/// Full-screen lock UI: auto-prompts Face ID, retry on failure, and a password
/// escape hatch that signs out (drops to the login screen).
struct LockScreen: View {
    let controller: AppLockController
    var onUsePassword: () -> Void

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: Spacing.lg) {
                Image(systemName: "faceid").font(.system(size: 56)).foregroundStyle(.accent)
                    .accessibilityHidden(true)
                Text("eSimplified Admin").font(.title2.weight(.semibold))
                Text("Locked").font(.subheadline).foregroundStyle(.secondary)
                Button("Unlock") { Task { await controller.authenticate() } }
                    .buttonStyle(.glassProminent).controlSize(.large)
                Button("Use password instead", action: onUsePassword)
                    .buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)
            }
            .padding(Spacing.xxl)
        }
        .task { await controller.authenticate() }   // auto-prompt on appear
    }
}

/// Opaque privacy cover shown while the app is inactive/backgrounded, so revenue
/// figures don't appear in the iOS app-switcher snapshot.
private struct PrivacyCover: View {
    var body: some View {
        ZStack { AppBackground(); Image("BrandMark").resizable().scaledToFit().frame(height: 64) }
    }
}

/// Wraps the signed-in shell with the lock + privacy overlays and scene-phase wiring.
struct LockContainer: ViewModifier {
    let controller: AppLockController
    var onUsePassword: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .overlay { if controller.isLocked { LockScreen(controller: controller, onUsePassword: onUsePassword) } }
            .overlay { if controller.isInactive && !controller.isLocked { PrivacyCover() } }
            .onAppear { controller.lockOnLaunch() }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active: controller.didBecomeActive()
                case .inactive, .background: controller.willResignActive()
                @unknown default: break
                }
            }
    }
}
#endif
```

> If `Spacing.lg`/`Spacing.xxl`/`AppBackground`/`.accent` differ from what `AdminTheme.swift` defines, adjust to the existing tokens (read `AdminTheme.swift`). The brand color and `BrandMark` asset already exist.

- [ ] **Step 2: Register `BiometricLock.swift` in the app target — 4 pbxproj edits.** Use the next free app UUIDs `A3000000000000000000060` (file ref) and `A3000000000000000000061` (build file).

  (a) In the PBXBuildFile section (near line 27, beside the other `… in Sources` lines), add:
  ```
  		A3000000000000000000061 /* BiometricLock.swift in Sources */ = {isa = PBXBuildFile; fileRef = A3000000000000000000060 /* BiometricLock.swift */; };
  ```
  (b) In the PBXFileReference section (near line 84), add:
  ```
  		A3000000000000000000060 /* BiometricLock.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = BiometricLock.swift; sourceTree = "<group>"; };
  ```
  (c) In the `EsimplifiedAdmin` PBXGroup children (the list ending at line 158, before `Assets.xcassets`), add:
  ```
  				A3000000000000000000060 /* BiometricLock.swift */,
  ```
  (d) In the app target Sources phase `A300000000000000000000D` (the `files = (…)` ending near line 286), add:
  ```
  				A3000000000000000000061 /* BiometricLock.swift in Sources */,
  ```

- [ ] **Step 3: Add `NSFaceIDUsageDescription` to `EsimplifiedAdmin/Info.plist`.** Read the plist, then add inside the top-level `<dict>`:
  ```xml
  	<key>NSFaceIDUsageDescription</key>
  	<string>Unlock the app with Face ID.</string>
  ```
  (Short reason; must not contain the app name — the system adds it.)

- [ ] **Step 4: Apply the lock container on iOS.** In `EsimplifiedAdminApp.swift`, give `AdminAppModel` an iOS lock controller and wrap the shell. Add to `AdminAppModel` (iOS-only):
  ```swift
  #if os(iOS)
  lazy var lock = AppLockController(isEnabled: { [weak self] in self?.biometricEnabled ?? false })
  #endif
  ```
  Update `AdminRootView`'s signed-in branch:
  ```swift
  } else {
      #if os(iOS)
      AdminShell(model: model)
          .environment(\.tokenProvider, model.sessionManager)
          .modifier(LockContainer(controller: model.lock, onUsePassword: { model.logout() }))
      #else
      AdminShell(model: model)
          .environment(\.tokenProvider, model.sessionManager)
      #endif
  }
  ```

- [ ] **Step 5: Build both platforms.**
```bash
xcodebuild -project Esimplified.xcodeproj -scheme EsimplifiedAdmin -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Esimplified.xcodeproj -scheme EsimplifiedAdmin -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```
Expected: both succeed (Mac ignores the iOS-only file).

- [ ] **Step 6: Manual run check (iOS Simulator).** Run the app; since `biometricEnabled` defaults to `false`, the lock must NOT appear yet (it's enabled in Task 9). Confirm the app launches straight to the shell and still loads data. (Full lock behavior is validated at the end of Task 9.)

- [ ] **Step 7: Commit**
```bash
git add EsimplifiedAdmin/BiometricLock.swift EsimplifiedAdmin/Info.plist EsimplifiedAdmin/EsimplifiedAdminApp.swift Esimplified.xcodeproj/project.pbxproj
git commit -m "feat(admin): iOS biometric lock — controller, lock screen, privacy cover

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Enrollment prompt (post-login) + Profile toggle

**Files:**
- Modify: `EsimplifiedAdmin/LoginView.swift` (flag enrollment offer on iOS)
- Modify: `EsimplifiedAdmin/EsimplifiedAdminApp.swift` (enrollment alert state + presentation)
- Modify: `EsimplifiedAdmin/ProfileScreen.swift` (biometric toggle, iOS)

**Interfaces:**
- Consumes: `model.setBiometricEnabled(_:)`, `model.biometricEnabled`, `AppLockController` (iOS), `LAContext` capability check.
- Verified by build + manual run on iOS (and a Mac build to confirm the toggle is hidden there).

- [ ] **Step 1: Offer enrollment after first sign-in (iOS).** In `EsimplifiedAdminApp.swift`, add iOS-only state to `AdminAppModel`:
  ```swift
  #if os(iOS)
  var offerBiometricEnrollment = false
  #endif
  ```
  In `LoginView.finish(_:)` (after `model.adopt(session)`), set the flag when biometrics are available and not already enabled:
  ```swift
      model.adopt(session)
      #if os(iOS)
      if !model.biometricEnabled, LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
          model.offerBiometricEnrollment = true
      }
      #endif
  ```
  Add `import LocalAuthentication` at the top of `LoginView.swift` (guard with `#if os(iOS)` import if it doesn't compile on macOS — `LocalAuthentication` exists on macOS too, so a plain import is fine, but the `canEvaluatePolicy` call is already inside `#if os(iOS)`).

- [ ] **Step 2: Present the enrollment alert.** In `AdminRootView`'s iOS signed-in branch, attach an alert bound to `model.offerBiometricEnrollment`:
  ```swift
      AdminShell(model: model)
          .environment(\.tokenProvider, model.sessionManager)
          .modifier(LockContainer(controller: model.lock, onUsePassword: { model.logout() }))
          .alert("Enable Face ID?", isPresented: $model.offerBiometricEnrollment) {
              Button("Enable") { model.setBiometricEnabled(true) }
              Button("Not Now", role: .cancel) {}
          } message: {
              Text("Require Face ID each time you open the app. Your session stays signed in in the background.")
          }
  ```
  (`$model.offerBiometricEnrollment` needs `@Bindable var model` — already the case in `AdminRootView`.)

- [ ] **Step 3: Add the Profile toggle (iOS only).** In `ProfileScreen.swift`, the view needs access to the model's biometric state. Pass two closures from `AdminShell` rather than the whole model, to keep `ProfileScreen`'s `session`-based API. In `AdminShell.swift`'s `detail`, change the profile case:
  ```swift
  case .profile:
      if let session = model.session {
          ProfileScreen(session: session, onLogout: { model.logout() },
                        biometricEnabled: model.biometricEnabled,
                        setBiometricEnabled: { model.setBiometricEnabled($0) })
      }
  ```
  In `ProfileScreen.swift`, add the two properties:
  ```swift
      var biometricEnabled: Bool = false
      var setBiometricEnabled: (Bool) -> Void = { _ in }
  ```
  And add an iOS-only section (e.g. after the `Security` section):
  ```swift
      #if os(iOS)
      Section("App lock") {
          Toggle("Require Face ID to open", isOn: Binding(
              get: { biometricEnabled },
              set: { setBiometricEnabled($0) }))
          if biometricEnabled {
              Text("The app locks on launch and after a few minutes in the background. Your session refreshes in the background.")
                  .font(.footnote).foregroundStyle(.secondary)
          }
      }
      #endif
  ```

- [ ] **Step 4: Build both platforms.**
```bash
xcodebuild -project Esimplified.xcodeproj -scheme EsimplifiedAdmin -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Esimplified.xcodeproj -scheme EsimplifiedAdmin -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```
Expected: both succeed; the App-lock section is absent on the Mac build.

- [ ] **Step 5: Manual run check (iOS Simulator with a Face ID device).** With Simulator → Features → Face ID → Enrolled:
  1. Sign in → the "Enable Face ID?" alert appears → tap Enable.
  2. Background the app > 3 min (or set grace low temporarily) and return → lock screen appears → Features → Face ID → Matching Face → unlocks.
  3. Verify data still loads after unlock (refresh ran underneath).
  4. In Profile, toggle off → background/return → no lock.

- [ ] **Step 6: Commit**
```bash
git add EsimplifiedAdmin/LoginView.swift EsimplifiedAdmin/EsimplifiedAdminApp.swift EsimplifiedAdmin/ProfileScreen.swift EsimplifiedAdmin/AdminShell.swift
git commit -m "feat(admin): biometric enrollment prompt + Profile toggle (iOS)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Widget + Siri adopt `SessionManager`

**Files:**
- Modify: `EsimplifiedWidget/RevenueProvider.swift`
- Modify: `EsimplifiedAdmin/AdminSiri.swift`

**Interfaces:**
- Consumes: `SessionManager`, `LiveAPIClient(host:tokenProvider:)`.
- Both run with the app closed, so their `SessionManager` uses `refreshEnabled: true` (a running widget/Siri implies a persistent session) and a no-op `onChange`. This removes their hand-rolled `expiresAt <= Date()` checks and gains carry-forward + coalescing.
- Verified by both build commands (widget is embedded in the app build).

- [ ] **Step 1: Widget.** In `RevenueProvider.fetchEntry()`, replace the manual expiry/refresh block + client construction. Replace lines 53-67 (`guard var session …` through `let client = LiveAPIClient(…)`) with:
```swift
        guard let session = try? store.load() else {
            return RevenueEntry(date: Date(), content: .needsAuth)
        }
        guard let auth = authClient() else {
            return RevenueEntry(date: Date(), content: .needsAuth)
        }
        let manager = SessionManager(session: session, store: store, authClient: auth, refreshEnabled: true)
        let client = LiveAPIClient(host: session.host, tokenProvider: manager)
```
The existing `do { let stats = try await client.get(...) } catch APIError.authExpired { .needsAuth } catch { .unavailable }` block stays — `client.get` now refreshes-on-use and retries on 401 internally, and throws `authExpired` only when the refresh token is truly dead.

- [ ] **Step 2: Siri.** In `AdminSiri.swift` `RevenueIntentSupport.fetch()`, replace the manual block (lines 15-21) with:
```swift
        let store = KeychainSessionStore()
        guard let session = try? store.load() else { throw RevenueIntentError.notSignedIn }
        guard let auth = authClient() else { throw RevenueIntentError.notSignedIn }
        let manager = SessionManager(session: session, store: store, authClient: auth, refreshEnabled: true)
        let client = LiveAPIClient(host: session.host, tokenProvider: manager)
```
The `do { … } catch APIError.authExpired { throw .notSignedIn }` block stays.

- [ ] **Step 3: Build both platforms** (the widget is embedded, so the app build compiles it):
```bash
xcodebuild -project Esimplified.xcodeproj -scheme EsimplifiedAdmin -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Esimplified.xcodeproj -scheme EsimplifiedAdmin -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```
Expected: both succeed.

- [ ] **Step 4: Commit**
```bash
git add EsimplifiedWidget/RevenueProvider.swift EsimplifiedAdmin/AdminSiri.swift
git commit -m "refactor(widget,siri): refresh via SessionManager (carry-forward + coalescing)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Final verification

- [ ] **Step 1: Full kit test suite** — `cd EsimplifiedKit && swift test` → all green (existing 47 + new SessionManager/BiometricGate/APIClientRefresh + biometric-flag tests).
- [ ] **Step 2: Both app builds** (commands above) → succeed.
- [ ] **Step 3: Confirm no stale fixed-token sites remain** — `grep -rn "accessToken: session.accessToken" EsimplifiedAdmin/ EsimplifiedWidget/` → no results.
- [ ] **Step 4: Manual smoke (iOS + Mac):** iOS — biometric on: lock on launch + after-grace, unlock, data loads, long-session no longer dies; biometric off: signs out on token expiry. Mac — no lock, session stays alive via refresh.
- [ ] No commit needed unless fixes were made.
