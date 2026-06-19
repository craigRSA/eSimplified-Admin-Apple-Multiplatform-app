# eSimplified Admin — Native Apple App design

A native **SwiftUI multiplatform** app (macOS 14 / iPadOS 17 / iOS 17) that
reimplements a **curated subset** of the existing Next.js admin front end
(`~/WebstormProjects/admin_front_end/`), over the shared `EsimPulseKit` engine
already built for eSim Pulse. Read-mostly admin client of the existing backend;
no backend changes.

## Scope (curated)

Login (foundation) + these screens, chosen by the product owner:

| # | Screen | Backend scope (read) | Notes |
|---|--------|----------------------|-------|
| 1 | Dashboard | `statistics:read` | Revenue/stats; logic already exists in `EsimPulseKit`. |
| 2 | Customers | `customer:read` | List + per-customer detail. |
| 3 | Order History | `order:read` | Searchable/filterable list + detail. |
| 5 | Search | `search:read` | Global search (tenant-scoped). |
| 10 | Inventory | `inventory:read` | eSIM/SIM stock. |
| 12 | Agent Order | `agent_order:read` | Place an order on behalf of a customer/agent. |
| 13 | Agent Order Approvals | `agent_approval:read` | Approve pending agent orders. |
| 19 | Profile | — (always) | The signed-in admin's own profile/settings. |

**Explicitly out of scope** (web app has them; not ported): Change Order,
Refund Requests, Wallets, Voucher Validation, KYC, Packages, Tenants,
Translations, White List, Users, Permissions/Groups.

## Platform & architecture

- **One SwiftUI multiplatform app target** (`eSimplifiedAdmin`) for macOS, iPadOS,
  iOS. All non-UI logic lives in the **`EsimPulseKit`** Swift package (already
  `.macOS(.v14)` + `.iOS(.v17)`), unit-tested from the command line.
- **Adaptive shell:** `NavigationSplitView` — sidebar of sections on Mac & iPad;
  collapses to a stacked/tab layout on iPhone. One section list, three form
  factors.
- **Reuse:** the existing `Credentials`, `KeychainCredentialStore`,
  `DashboardStats`, statistics client, and `MockURLProtocol` test harness carry
  over; new shared types are added to the package.

## Authentication (matches the web app exactly)

OAuth2 **password grant** against the existing backend:

- `POST {host}/auth/token/`
- Headers: `Authorization: Basic base64(CLIENT_ID:CLIENT_SECRET)`,
  `Content-Type: application/x-www-form-urlencoded`, optional `X-Trusted-Device`.
- Body: `grant_type=password&username=<u>&password=<p>`.
- Response: `{ access_token, refresh_token, token_type, expires_in, scope,
  account_type, requires_2fa?, "2fa_token"? }`.
- Reject login unless `account_type == "human"` and the token carries at least
  one `<resource>:read` scope.
- Subsequent API calls send `Authorization: Bearer <access_token>` — the same
  token the eSim Pulse dashboard/widget already use.
- **Refresh:** when `access_token` nears `expires_in`, exchange `refresh_token`
  for a new access token; on refresh failure, return to login.

**Scope-driven navigation:** the sidebar shows only sections whose `:read` scope
is present in the token (e.g. hide Inventory if no `inventory:read`). Profile is
always shown.

**Client-credentials decision:** the web app keeps `CLIENT_ID`/`CLIENT_SECRET`
server-side. A native app has no server, so these are **embedded in the build**
(via an `.xcconfig` / build setting, not committed to git). Acceptable for an
internal, staff-only admin tool. If that is later judged too sensitive, the
alternative is a thin token-exchange proxy — out of scope here.

### Two-factor authentication (TOTP) — in v1

The backend supports TOTP 2FA; v1 includes both the login challenge and
enrollment ("add my 2FA key").

**Login challenge:** if `POST /auth/token/` responds with `requires_2fa` and a
`2fa_token`, prompt for the 6-digit code, then
`POST /auth/token/2fa/` with the `2fa_token` + code (+ optional
`remember_device` → store the returned trusted-device token in Keychain and send
it as `X-Trusted-Device` on future logins to skip the challenge).

**Enrollment / management** (reached from Profile or a Security screen):
- `GET /2fa/status/` → `{ totp_enabled }`.
- `POST /2fa/setup/` → `{ method: "totp", otpauth_url, ... }`. Render
  `otpauth_url` as a **QR code** (natively via CoreImage `CIQRCodeGenerator` —
  no third-party dependency) and also show the embedded secret as selectable
  text, so the user adds it to their authenticator app.
- `POST /2fa/verify/` with a code → confirm and enable.
- `POST /2fa/disable/` with a code → turn off.

**Deferred:** WebAuthn/passkeys (`/2fa/verify/` passkey path, `ASAuthorization`)
— a later phase. v1 uses TOTP. If the backend forces a passkey-only account,
surface a clear message.

## Shared engine additions (`EsimPulseKit`)

- **`APIClient`** — generalizes `LiveStatisticsClient`: builds `{host}/<path>`
  requests with `Bearer` auth + `Accept: application/json`, decodes `Decodable`
  responses, maps status/transport failures to a typed error
  (`authExpired` / `unreachable` / `notFound` / `decoding`). The existing
  `StatisticsClient` becomes a thin caller of `APIClient`.
- **`AuthClient`** — performs the password grant + refresh against `/auth/token/`,
  returns a `Session { accessToken, refreshToken, expiresAt, scopes,
  accountType }`. Handles the **2FA login challenge**: surfaces a
  `requires2FA(token:)` result, and a `verify2FA(token:code:rememberDevice:)`
  call to `/auth/token/2fa/` that returns a `Session`.
- **`TwoFactorClient`** — `status()` (`GET /2fa/status/`),
  `beginSetup()` (`POST /2fa/setup/` → `otpauth_url` + secret),
  `verify(code:)` (`POST /2fa/verify/`), `disable(code:)` (`POST /2fa/disable/`).
- **`Session` / token storage** — extend `KeychainCredentialStore` to persist the
  host + access/refresh tokens + expiry + scopes (single Keychain item).
- **Domain models** (added per screen slice, not all upfront): `Customer`,
  `Order`, `InventoryItem`, `AgentOrder`, etc. — `Decodable`, money as `Decimal`,
  tolerant decimal decoding via the existing `FlexibleDecimal`.

## App shell (`eSimplifiedAdmin` target)

- `RootView`: shows **Login** when no valid session, else the **adaptive shell**.
- `AppModel` (`@Observable @MainActor`): holds the `Session`, the `APIClient`,
  exposes the visible sections (filtered by scope), handles logout + refresh.
- `Section` enum drives the sidebar; each section maps to a destination view.
  Foundations ships the shell with placeholder destinations; each curated screen
  is filled in by its own later slice.

## Phased roadmap (each phase = its own spec → plan → implementation)

1. **Foundations (this slice):** `APIClient`, `AuthClient` + refresh, session
   Keychain storage, login screen, adaptive shell + scope-gated section list,
   placeholder destinations. Unit-tested engine; build/run UI.
2. **Dashboard** — port the existing stats screen into the shell.
3. **Order History** — list + filter + detail (`order:read`).
4. **Customers** — list + detail (`customer:read`).
5. **Search** — global search (`search:read`).
6. **Inventory** (`inventory:read`).
7. **Agent Order + Agent Order Approvals** (`agent_order:read`, `agent_approval:read`).
8. **Profile**.

Each screen slice discovers its exact endpoints/response shapes from the web
app's API calls at spec time, and is built TDD in the package (client + models)
plus a SwiftUI screen.

## Foundations slice — detail (first plan target)

**Files (engine):**
- `Sources/EsimPulseKit/APIClient.swift` — `APIClient` protocol + `LiveAPIClient`.
- `Sources/EsimPulseKit/AuthClient.swift` — `AuthClient` + `Session` + grant /
  refresh / 2FA-challenge verify.
- `Sources/EsimPulseKit/TwoFactorClient.swift` — status / setup / verify / disable.
- Extend `KeychainCredentialStore` for session + trusted-device-token persistence.
- Tests: `APIClientTests`, `AuthClientTests` (password grant, refresh, 2FA
  challenge), `TwoFactorClientTests` (all via `MockURLProtocol`), session
  round-trip tests with `InMemoryCredentialStore`.

**Files (app target — added to the Xcode project):**
- `eSimplifiedAdmin/eSimplifiedAdminApp.swift` — `@main`, `AppModel`, `RootView`.
- `eSimplifiedAdmin/LoginView.swift` — host + username + password; on
  `requires_2fa`, a 6-digit code step + "remember this device" toggle.
- `eSimplifiedAdmin/TwoFactorSetupView.swift` — enroll TOTP: shows the QR
  (CoreImage) + secret, then verifies a code to enable; reachable from the shell.
- `eSimplifiedAdmin/AdminShell.swift` — `NavigationSplitView`, scope-gated sections,
  placeholder destinations, entry point to 2FA setup.
- iOS + macOS entitlements (network client; sandbox on macOS).

**Acceptance:**
- Logging in with valid staff credentials stores a session and lands on the
  adaptive shell; the sidebar shows only scope-permitted sections.
- A 2FA-required account is challenged for a TOTP code and logs in on success;
  "remember this device" skips the challenge next time.
- A user can enroll a new TOTP key: scan the QR (or copy the secret) into an
  authenticator and confirm a code to enable; can disable with a code.
- Token auto-refreshes; logout clears the Keychain and returns to login.
- Builds and runs on macOS and the iOS Simulator.

## Testing

- Engine (`APIClient`, `AuthClient`, refresh, scope parsing, session storage)
  unit-tested from the CLI via `swift test` with the `MockURLProtocol` pattern.
- UI verified by build + run (macOS app + iOS Simulator); no device signing
  required to validate Foundations.

## Conventions (inherited)

Money always `Decimal`; tolerant string-or-number decimal decoding; Foundation /
SwiftUI / no third-party deps; tokens only in Keychain; TDD for engine code.
