# Biometric sign-in + token refresh — design

**Date:** 2026-06-20
**Status:** Design — pending implementation plan
**Targets:** `EsimplifiedKit`, `EsimplifiedAdmin`, `EsimplifiedWidget`

## Problem

Two related issues with how the OAuth session is kept alive:

1. **Refresh doesn't keep a long-open app alive.** Today the only refresh trigger is
   `AdminAppModel.refreshSessionIfNeeded()`, called once from `AdminShell`'s `.task`.
   There is no timer, no foreground hook, and no per-request check. The access token
   lasts ~9h, so when the app sits open (or backgrounded without a full relaunch) past
   expiry, every screen 401s and only a cold relaunch fixes it. Observed symptom: *app
   stays signed in but stops loading data until relaunched.*

2. **No biometric protection.** There is no Face ID / Touch ID gate on the app at all.

The request: an opt-in **biometric sign-in** mode where every app open requires Face ID
while the OAuth refresh happens independently in the background; when biometric sign-in
is *not* enabled, the app does not refresh — it signs the user out when the access token
expires.

The refresh request format itself is **not** the bug. It was verified against the web
source of truth (`admin_front_end/src/lib/utils/auth.ts`): the web app refreshes with
`client_id`/`client_secret` in the form body and **no** Basic auth header, which is
exactly what `LiveAuthClient.refresh` already does. (Basic auth is only used on the
password/login grant.) Django OAuth Toolkit accepts either form, so the user's
`-u CLIENT_ID:CLIENT_SECRET` curl is an equivalent, not a discrepancy.

## Behavior model

A single user-facing switch — **"Biometric sign-in"** (off by default) — controls both
whether the session is kept alive and whether a Face ID gate is shown.

| Condition | Refresh-on-use active? | Face ID gate on open? | On access-token expiry |
|---|---|---|---|
| iOS, biometric **on** | yes | yes (cold launch + foreground after grace) | refresh silently |
| iOS, biometric **off** | no | no | **sign out → login screen** |
| macOS (always) | yes | no | refresh silently |

Derived rules:

- **Refresh-on-use** is active when `biometricEnabled == true` **or** `os == macOS`.
- **Face ID gate** is active only on iOS when `biometricEnabled == true`.
- **Sign-out-on-expiry** happens only on iOS when `biometricEnabled == false`.

The password is **never** stored. When biometric sign-in is enabled, the persisted
credential is the OAuth **refresh token** in the Keychain, and Face ID gates its *use* —
not a stored password.

### Enrollment

- After the first successful password (+2FA) sign-in, prompt: *"Enable Face ID to stay
  signed in?"* (only when the device can evaluate biometrics).
- A toggle in `ProfileScreen` enables/disables it later.
- The `biometricEnabled` flag is stored in the Keychain alongside the session (not
  `UserDefaults`), so it shares the session's protection and access group.
- The enrollment prompt and the Profile toggle are **iOS-only**. macOS always refreshes
  and never gates (per the truth table), so the flag is irrelevant there and the toggle
  is hidden on Mac.

### The Face ID screen does double duty

When biometric sign-in is on, opening the app shows the Face ID screen. On a successful
evaluation it ensures a valid session:

1. Access token still valid → unlock, show content.
2. Access token expired → refresh using the stored refresh token (behind the gate),
   then unlock.
3. Refresh rejected (`authExpired` — refresh token revoked/expired) → fall through to
   the password **login** screen.

This means "Face ID logs you back in" and "Face ID unlocks the app" are the *same*
screen. There is no separate stored-password re-login path.

## Architecture

### Part A — refresh-on-use (`EsimplifiedKit`)

New `actor SessionManager` owns the live session and serializes refreshes. It is the
single chokepoint that vends a currently-valid access token.

```
public actor SessionManager {
    init(store: SessionStore, authClient: AuthClient, refreshBufferSeconds: TimeInterval = 60,
         refreshPolicy: RefreshPolicy)

    func currentSession() -> Session?
    func validAccessToken() async throws -> String   // refreshes if needed
    func adopt(_ session: Session)                    // after login / 2FA
    func clear()
}
```

`validAccessToken()`:

1. If there is no session → throw `APIError.authExpired`.
2. If `expiresAt.timeIntervalSinceNow > refreshBufferSeconds` (≈60s clock-skew buffer)
   → return the current access token.
3. Otherwise the token is close/passed:
   - If `refreshPolicy` says **don't refresh** (iOS + biometric off) → clear the session
     and throw `APIError.authExpired` (caller signs out).
   - Else refresh: if a refresh is already in flight, await that same `Task`
     (single-flight coalescing — concurrent requests trigger exactly one refresh); the
     winner calls `authClient.refresh`, **merges** the result (see rotation below),
     persists via `SessionStore`, and returns the new access token.

**Refresh-token rotation / carry-forward.** `AuthClient.makeSession` currently does
`refreshToken = json["refresh_token"] ?? ""`, which would overwrite a good token with an
empty string if the server omits a rotated token, permanently breaking the chain. Fix:
the merge step keeps the **previous** refresh token when the refresh response omits one,
and adopts the new one when present (rotation). This is done at the `SessionManager` merge
boundary so `makeSession` stays a pure decoder; it may surface an empty refresh token,
and the manager fills it in from the prior session.

**`RefreshPolicy`** is a small injected value/closure expressing the truth-table rule
(refresh allowed when biometric-on or macOS). Keeping it injectable keeps `SessionManager`
unit-testable and platform-agnostic.

**`LiveAPIClient`** changes from holding a frozen `accessToken: String` to holding a token
provider it calls at the top of each request:

```
public protocol AccessTokenProviding: Sendable { func validAccessToken() async throws -> String }
// SessionManager conforms. A trivial static provider preserves the existing
// init(host:accessToken:) for tests and any call site that wants a fixed token.
```

So the freshness check happens on **every** request automatically — present and future
call sites included — rather than each screen remembering to check.

**Reuse across surfaces.** The widget (`RevenueProvider`) and Siri (`AdminSiri`) currently
hand-roll `if session.expiresAt <= Date() { refresh }`. They adopt `SessionManager` too,
removing the duplicated logic. Their `RefreshPolicy` always allows refresh (a widget/Siri
running implies the user opted into a persistent session, and they have no UI to gate).

### Part B — biometric lock (`EsimplifiedAdmin`, iOS only)

`AppLockController` (`@Observable`, app target, wrapped in `#if os(iOS)`):

- State: `.unlocked` / `.locked` / `.unavailable`.
- **Locks on:** cold launch (when a session exists and biometric is enabled); foreground
  after the app was backgrounded longer than a **3-minute** grace interval. A quick
  app-switch within the grace window does not re-prompt.
- **Grace** is implemented by recording a `backgroundedAt` timestamp on
  `scenePhase == .background` and comparing on `.active`. (Decision is a pure function in
  the kit — see Testing.)
- **Unlock:** `LAContext.evaluatePolicy(.deviceOwnerAuthentication, ...)` — Face ID /
  Touch ID **with device-passcode fallback**, so a failed/unenrolled biometric still has a
  path in. Auto-prompts on the lock screen; offers a "Use password instead" escape hatch
  that drops to the login screen (clears the session), and on success runs the
  ensure-valid-session steps above.
- **Privacy cover:** when `scenePhase` is `.inactive`/`.background`, show an opaque cover
  so revenue figures don't appear in the iOS app-switcher snapshot.
- **Graceful degrade:** if `LAContext.canEvaluatePolicy` is false (no biometrics *and* no
  passcode), do not trap the user out — treat as `.unavailable` and don't gate. (Biometric
  sign-in can't be enabled on such a device in the first place.)

### Keychain accessibility fix (`EsimplifiedKit`, prerequisite)

`KeychainSessionStore.write()` sets no `kSecAttrAccessible`, defaulting to
`kSecAttrAccessibleWhenUnlocked` — which prevents the **widget and background refresh from
reading the session while the device is locked**. Change the write query to
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`:

- readable by background/extension processes after the first post-boot unlock (needed for
  the widget and silent refresh), and
- never synced to iCloud Keychain or device backups (appropriate for bearer tokens).

This is independent of the biometric feature but is a prerequisite for *reliable*
independent refresh, so it ships as part of this work.

**Note:** we deliberately do **not** use `SecAccessControlCreateWithFlags(.biometryCurrentSet)`
on the token. OS-level biometry protection would block the widget and the silent in-app
refresh (background reads fail with `errSecInteractionNotAllowed`) and would wipe the token
when the user changes passcode/enrollment. The biometric requirement is enforced as a UI
gate (`AppLockController`), the established app-lock pattern, leaving the token readable for
independent background refresh.

### Gating wiring (`EsimplifiedAdminApp` / `AdminRootView`)

```
if session == nil            -> LoginView
else if locked (iOS, bio on) -> LockScreen (Face ID)   // overlays/covers content
else                         -> AdminShell
```

`AdminAppModel` owns the `SessionManager` and (on iOS) the `AppLockController`, bridges the
manager's session to its `@Observable session` so scope-gated UI and per-screen reloads
still react, and removes the old one-shot `refreshSessionIfNeeded()`.

## Error handling

- `validAccessToken()` throws `APIError.authExpired` when there is no session, when refresh
  is disallowed by policy and the token has expired, or when refresh is rejected. The app
  treats `authExpired` from the manager as "sign out → login."
- Network-unreachable during refresh throws `APIError.unreachable`; the session is **not**
  cleared (transient) and the caller surfaces the existing "couldn't reach the server"
  message; the next request retries.
- Biometric evaluation failure/cancel keeps the lock screen up with a retry and the
  password escape hatch.

## Testing

Pure / unit-testable in `EsimplifiedKit` (with fakes for `AuthClient` and an in-memory
`SessionStore`):

- `validAccessToken` returns the current token when far from expiry; refreshes within the
  buffer; throws `authExpired` when policy disallows refresh on an expired token.
- Concurrent `validAccessToken` calls on an expired token trigger **exactly one** refresh
  (single-flight coalescing).
- Refresh-token carry-forward: a refresh response omitting `refresh_token` keeps the prior
  one; one containing a new token rotates to it.
- The re-lock decision (`shouldRelock(backgroundedAt:now:grace:)`) is a pure function with
  table-driven tests.
- `KeychainSessionStore` round-trips with the new accessibility attribute set.

`LAContext` evaluation, the lock/privacy SwiftUI overlays, and scene-phase wiring are app
shells verified by build + run on Mac and iOS Simulator/device.

## Out of scope (YAGNI)

- A 401→refresh→retry wrapper around API responses. Refresh-on-use (checking before each
  request) is sufficient for the reported symptom; a response-side retry is not added.
- Per-screen or configurable grace interval. Fixed at 3 minutes.
- Biometric gate on macOS.
- Storing credentials/password for re-login.
