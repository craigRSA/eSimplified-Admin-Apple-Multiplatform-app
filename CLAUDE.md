# eSimplified Admin

A native Apple (Mac / iPad / iPhone) reimplementation of a curated subset of the
eSimplified web admin front end, plus a WidgetKit widget, over one shared engine
(`EsimplifiedKit`). Read-mostly client of the existing eSimplified backend.

> History: the repo began as "eSim Pulse" — a small read-only revenue *glance*
> app + widget. That glance app has been **removed**; the **Admin app is now the
> single product**, and the widget is embedded inside it. A few historical names
> linger (git dir is still `eSimPulse/`; the Xcode project is
> `Esimplified.xcodeproj`). Older docs under `docs/specs` / `docs/plans` describe
> the retired glance app — treat this file as the source of truth.

## Structure

```
EsimplifiedKit/    ← local Swift package: ALL testable logic (swift test, no Xcode)
EsimplifiedAdmin/  ← the app target (Mac + iPad + iPhone), imports EsimplifiedKit
EsimplifiedWidget/ ← WidgetKit extension, EMBEDDED in the Admin app
docs/backend/      ← read-only API additions requested from the backend team
docs/specs|plans/  ← historical (glance app + admin foundations)
```

Two targets over one engine. The widget is embedded in the Admin app's "Embed App
Extensions" phase (bundle id `io.esimplified.admin.widget` inside
`io.esimplified.admin`). Logic lives in the package so it has real unit tests;
the app/widget are UI shells verified by build + run.

### Engine (`EsimplifiedKit`) — key types
- `Session` / `SessionStore` / `KeychainSessionStore` — OAuth session (access +
  refresh token, `expiresAt`, scopes) in the Keychain.
- `AuthClient` / `LiveAuthClient` — OAuth2 password grant, refresh, 2FA verify.
- `APIClient` / `LiveAPIClient` — `GET {host}/api/…` with Bearer auth.
- `APIError` — `authExpired` (401), `notFound` (404), `requestFailed(status,
  serverMessage)` (everything else, incl. 403 — carries the server's reason),
  `unreachable`, `decoding`. (Genuine task cancellation throws `CancellationError`,
  not `.unreachable`.)
- `AdminDashboardStats` (+ `StatsPeriod`, `HourPoint`, `LabeledCount`,
  `MonthRevenue`, `TenantRevenueSlice`) — the `/api/statistics/` response.
- `Order`/`OrdersPage`, `Customer`/`CustomersPage`, `EsimSummary`/`EsimDetail`
  (+ `EuiccProfile`, `EsimPackage`, `OpenDataSession`, `EsimLocation`,
  `Whitelist`, `EsimSession`), `Inventory`, `MeUser`, `Tenant`, `TwoFactorClient`.
- `FlexibleDecimal` — decodes money fields that arrive as JSON string OR number.
- Legacy glance-era types still present but UNUSED by any shipping target:
  `Credentials`, `KeychainCredentialStore`, `DashboardStats`,
  `StatisticsClient`/`LiveStatisticsClient`, `DashboardViewModel` (kept only
  because their tests still run; safe to delete with their tests).

### App (`EsimplifiedAdmin`)
- `AdminShell` — `NavigationSplitView`; sidebar sections gated by token scopes;
  tenant picker + auto-refresh menu in the toolbar; macOS bottom status bar with
  a UTC clock; macOS menu-bar revenue item (`MenuBarRevenue`).
- Screens: `DashboardScreen` (hero "today's gross volume", hourly
  today-vs-yesterday chart, date-range dropdown incl. `year_to_date`,
  "X vs previous" card, per-tenant/per-month bars — all with tap tooltips),
  `OrdersScreen` (columnar `Table` on Mac/iPad, rich rows on iPhone; whole row
  deep-links to the customer), `CustomersScreen`, `SearchScreen` (Customer +
  ICCID modes), `CustomerDetailScreen` (profile, eSIM list, full eSIM panel +
  View Locations/Packages/Sessions/Whitelist sheets, orders), `InventoryScreen`,
  `AgentApprovalsScreen`, `ProfileScreen` (2FA enable/disable).
- `AdminSiri.swift` — App Intents (`TodaysRevenueIntent`,
  `YesterdayRevenueIntent`, `RevenueVsYesterdayIntent`) + `AppShortcutsProvider`.
  Must live in the **app target** (not the package) for App Intents metadata
  extraction to discover them.

## Conventions / gotchas

- **Platform floor: iOS 26 / macOS 26** for the Admin target (Liquid Glass —
  `.glassEffect`, `.glassProminent`). The widget target is iOS 17 / macOS 14; the
  kit is `.iOS(.v17)` / `.macOS(.v14)`. Swift 5.9+.
- **Money is always `Decimal`**; API decimals may be strings or numbers →
  `FlexibleDecimal`. Guard chart values for NaN/inf (`ProgressView`/Charts crash
  on non-finite).
- **No third-party dependencies** — Foundation / SwiftUI / AppKit / Charts /
  AppIntents / XCTest only.
- **Secrets:** OAuth client id/secret come from a **gitignored**
  `EsimplifiedAdmin/Secrets.xcconfig` (`ESP_CLIENT_ID` / `ESP_CLIENT_SECRET`),
  surfaced via `Info.plist` `$(ESP_CLIENT_ID)` etc. Never commit real creds; the
  committed `Info.plist` only has `$()` placeholders + `Secrets.example.xcconfig`.
- **Host is configured, not asked:** `Info.plist` `ESPHost =
  https://live.esimplified.io` (the ROOT — the app appends `/api/…` and
  `/auth/…`). No host field in the UI.
- **Auth lives in the Keychain** (never UserDefaults). App ↔ widget share the
  session via a sole Keychain access group
  `$(AppIdentifierPrefix)io.esimplified.admin.shared` (in both entitlements). The
  app refreshes the token near `expiresAt` (token lasts ~9h); the widget refreshes
  on its own.
- **Trailing slashes matter:** Django 301-redirects slash-less paths and
  URLSession drops the `Authorization` header on the redirect → 401. Always hit
  the canonical `/…/` form (e.g. `/api/customers/{tenant}/{id}/`,
  `/api/esim/{iccid}/`).
- **iPhone nav cancels `.task`:** `NavigationSplitView` collapses on iPhone and
  cancels a detail screen's `.task` on navigation. Load via the `.reload(on:)`
  modifier (unstructured Task) — not `.task(id:)`.
- **Siri:** App Shortcut phrases must contain `\(.applicationName)`. Display name
  is "eSimplified Admin"; `CFBundleSpokenName` + `INAlternativeAppNames` add
  "eSimplified" as a spoken alias (re-indexes on launch, may need a reboot).
- **DEVELOPMENT_TEAM = 8GVFL9KS7M.** `project.pbxproj` is hand-authored (no Xcode
  GUI) — UUID prefixes A0=project, A2=widget, A3=admin app. Adding a file = 4
  edits (PBXBuildFile, PBXFileReference, group children, Sources phase).
- **`git push` is denied** in `.claude/settings.local.json`. Commit per change
  with the `Co-Authored-By: Claude` trailer; never push without explicit ask.
- Ground every API contract in the web source at
  `/Users/craig/WebstormProjects/admin_front_end/` (`src/app/actions/index.ts`,
  `src/lib/api.ts`, `src/types/index.ts`). Don't invent shapes.

## Auth flow
OAuth2 password grant: `POST {host}/auth/token/` (form-encoded + `Authorization:
Basic base64(clientID:clientSecret)`). 2FA challenge: `POST {host}/auth/token/2fa/`
(**JSON** `{two_fa_token, code, remember_device}`, no Basic auth). 2FA mgmt:
`/2fa/status|setup|verify|disable/` (JSON). The user's password may have a leading
space — never trim it.

## Commands

```bash
cd EsimplifiedKit && swift test          # core unit tests (69)
cd EsimplifiedKit && swift build         # compile the engine
# Build the app (embeds the widget). CODE_SIGNING_ALLOWED=NO for CI/sim checks.
xcodebuild -project Esimplified.xcodeproj -scheme EsimplifiedAdmin \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Esimplified.xcodeproj -scheme EsimplifiedAdmin \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

> Running on a physical device needs both targets signed (the shared-Keychain
> capability requires the build machine in the signing team's account). If an
> incremental build reports a stale type, `xcodebuild clean` the scheme.

## Status

Built & green (Mac + iOS): auth + 2FA, Dashboard (hero/hourly/date-range/charts),
Order History, Customers, Search, **full Customer Details** (eSIM panel + View
Locations/Packages/Sessions/Whitelist), Inventory, Agent Approvals, Profile,
embedded self-refreshing widget (hourly chart), macOS menu-bar item, and Siri
voice intents.

**Pending backend (read-only additions):** hourly today/yesterday series +
`year_to_date` date range — spec in
`docs/backend/2026-06-19-statistics-hourly-and-ytd.md`. The client already decodes
them and lights up when they ship.

**Deliberately not built:** write actions from the web customer_details page
(refund request, resend confirmation email) — the app is read-mostly.
