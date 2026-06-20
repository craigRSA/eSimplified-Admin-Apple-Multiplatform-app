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
        let sess = await mgr.currentSession()
        XCTAssertNil(sess, "expired + no-refresh clears the session")
    }

    func test_refresh_carriesForwardOldRefreshToken_whenResponseOmitsOne() async throws {
        let auth = FakeAuthClient(); auth.refreshReturnsEmptyRefreshToken = true
        let mgr = SessionManager(session: session(access: "acc-0", refresh: "ref-0", expiresIn: 0),
                                 store: InMemorySessionStore(), authClient: auth)
        _ = try await mgr.validAccessToken()
        let refreshToken = await mgr.currentSession()?.refreshToken
        XCTAssertEqual(refreshToken, "ref-0",
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

    func test_transientError_doesNotClearSession() async {
        let auth = FakeAuthClient()
        auth.refreshError = APIError.unreachable
        let mgr = SessionManager(session: session(access: "acc-0", refresh: "ref-0", expiresIn: 30),
                                 store: InMemorySessionStore(), authClient: auth, refreshBufferSeconds: 60)
        do {
            _ = try await mgr.validAccessToken()
            XCTFail("expected unreachable error")
        } catch {
            XCTAssertEqual(error as? APIError, .unreachable,
                           "transient error must propagate as-is, not authExpired")
        }
        let sess = await mgr.currentSession()
        XCTAssertNotNil(sess, "transient refresh error must not sign the user out")
    }

    func test_authExpiredDuringRefresh_invalidatesSession() async {
        let auth = FakeAuthClient()
        auth.refreshError = APIError.authExpired
        let mgr = SessionManager(session: session(access: "acc-0", refresh: "ref-0", expiresIn: 30),
                                 store: InMemorySessionStore(), authClient: auth, refreshBufferSeconds: 60)
        do {
            _ = try await mgr.validAccessToken()
            XCTFail("expected authExpired error")
        } catch {
            XCTAssertEqual(error as? APIError, .authExpired,
                           "revoked refresh token must throw authExpired")
        }
        let sess = await mgr.currentSession()
        XCTAssertNil(sess, "authExpired during refresh must invalidate the session")
    }

    func test_onChange_firesOnAdoptAndClear_notOnSilentRefresh() async throws {
        // Thread-safe recorder: a final class with a lock is the simplest Sendable approach.
        final class Recorder: @unchecked Sendable {
            private let lock = NSLock()
            private var _events: [Session?] = []
            func record(_ s: Session?) { lock.withLock { _events.append(s) } }
            var events: [Session?] { lock.withLock { _events } }
        }

        let recorder = Recorder()
        let auth = FakeAuthClient()
        let mgr = SessionManager(
            session: session(access: "acc-0", refresh: "ref-0", expiresIn: 30),
            store: InMemorySessionStore(), authClient: auth,
            refreshBufferSeconds: 60,
            onChange: { recorder.record($0) }
        )

        // Silent refresh (within-buffer) — onChange must NOT fire.
        _ = try await mgr.validAccessToken()
        let afterRefresh = recorder.events
        XCTAssertEqual(afterRefresh.count, 0, "silent refresh must not fire onChange")

        // adopt(_:) — onChange fires once with the adopted session.
        let adopted = session(access: "acc-adopted", refresh: "ref-adopted", expiresIn: 3600)
        await mgr.adopt(adopted)
        let afterAdopt = recorder.events
        XCTAssertEqual(afterAdopt.count, 1, "adopt must fire onChange once")
        XCTAssertEqual(afterAdopt.first??.accessToken, "acc-adopted")

        // clear() — onChange fires once with nil.
        await mgr.clear()
        let afterClear = recorder.events
        XCTAssertEqual(afterClear.count, 2, "clear must fire onChange once")
        XCTAssertNil(afterClear[1], "clear must pass nil to onChange")
    }
}
