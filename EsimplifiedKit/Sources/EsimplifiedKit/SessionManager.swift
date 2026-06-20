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
