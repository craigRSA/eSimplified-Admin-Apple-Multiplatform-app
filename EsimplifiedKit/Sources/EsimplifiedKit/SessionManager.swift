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
    private var onChange: @Sendable (Session?) -> Void

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

    public func setOnChange(_ handler: @escaping @Sendable (Session?) -> Void) { onChange = handler }

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
        // Fast path — runs before every request, so no Keychain I/O when our own
        // access token is still valid (a sibling rotating the refresh token can't
        // invalidate an access token we already hold).
        if current.expiresAt.timeIntervalSince(now()) > refreshBuffer {
            return current.accessToken
        }
        // Near expiry: a sibling (widget/Siri) may have already refreshed the shared
        // Keychain — adopt that before spending a network refresh.
        let synced = syncFromStore(preferred: current)
        if synced.expiresAt.timeIntervalSince(now()) > refreshBuffer {
            return synced.accessToken
        }
        return try await performRefresh(synced).accessToken
    }

    public func refreshedAccessToken(after staleToken: String) async throws -> String {
        guard let current = session else { throw APIError.authExpired }
        let synced = syncFromStore(preferred: current)
        // Another caller already rotated past the token that 401'd — use the new one.
        if synced.accessToken != staleToken { return synced.accessToken }
        return try await performRefresh(synced).accessToken
    }

    /// Coalesced, policy-gated refresh. Concurrent callers await the same Task.
    private func performRefresh(_ current: Session) async throws -> Session {
        if let inFlight = refreshTask { return try await inFlight.value }
        guard refreshEnabled else {
            // Expired and not allowed to refresh → invalidate and sign out.
            invalidate()
            throw APIError.authExpired
        }
        let task = Task { try await self.executeRefresh(startingFrom: current) }
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

    /// Refresh against the auth server, recovering once when another process
    /// (widget, Siri) already rotated the shared Keychain session.
    private func executeRefresh(startingFrom current: Session, retried: Bool = false) async throws -> Session {
        let synced = syncFromStore(preferred: current)
        guard !synced.refreshToken.isEmpty else { throw APIError.authExpired }

        // Another writer already refreshed — adopt their access token if still valid.
        if synced.refreshToken != current.refreshToken,
           synced.expiresAt.timeIntervalSince(now()) > refreshBuffer {
            return synced
        }

        let host = synced.host
        let oldRefresh = synced.refreshToken
        do {
            let refreshed = try await authClient.refresh(host: host, refreshToken: oldRefresh)
            // Carry forward the old refresh token if the server omitted a new one.
            return refreshed.refreshToken.isEmpty
                ? Session(host: refreshed.host, accessToken: refreshed.accessToken,
                          refreshToken: oldRefresh, expiresAt: refreshed.expiresAt,
                          scopes: refreshed.scopes, accountType: refreshed.accountType)
                : refreshed
        } catch let error as APIError where error == .authExpired {
            // Token rejected. If a sibling rotated the Keychain to a different token
            // mid-flight, try once with that; otherwise it's truly dead → sign out.
            if !retried, let stored = try? store.load(), stored.refreshToken != oldRefresh {
                return try await executeRefresh(startingFrom: stored, retried: true)
            }
            throw APIError.authExpired
        }
        // Non-authExpired errors (e.g. .unreachable) propagate untouched — transient.
    }

    /// Prefer the Keychain copy when the widget/Siri extension refreshed out-of-process.
    private func syncFromStore(preferred: Session) -> Session {
        guard let stored = try? store.load() else { return preferred }
        if stored.refreshToken != preferred.refreshToken || stored.expiresAt > preferred.expiresAt {
            session = stored
            return stored
        }
        return preferred
    }

    private func invalidate() {
        session = nil
        try? store.clear()
        onChange(nil)
    }
}
