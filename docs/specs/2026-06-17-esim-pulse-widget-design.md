# eSim Pulse — Desktop Widget design

A native macOS **WidgetKit** widget showing today's consolidated eSimplified
revenue, addable from the widget gallery to the Desktop / Notification Center.
Reuses `EsimPulseKit` (credential store, statistics client, decimal model)
wholesale; the existing app becomes the companion/config surface (and the
required container the widget ships inside).

## Sizes & content

- **Small (`systemSmall`):** `$<today>` headline + green/red delta-vs-yesterday arrow.
- **Medium (`systemMedium`):** the same, plus a 7-day revenue **sparkline**
  (dependency-free `Path`, drawn from `current.revenue_per_date`).

Currency symbol is hardcoded `$` (configurability remains Phase 3, matching the app).

## Data flow (self-updating)

- The widget runs its own `TimelineProvider`. Every ~20 min (system-budgeted
  hint via `.after` policy) it:
  1. Reads the Bearer token + host from the **shared Keychain** (written by the app).
  2. Calls `GET {host}/api/statistics/?date_range=last_7_days` via
     `LiveStatisticsClient`.
  3. Emits a single timeline entry rendering today's revenue, delta, and series.
- Stays current with the app closed. No shared cache; the widget is the fetcher.

## Token sharing

- Both the app and the widget extension declare the same shared Keychain access
  group `$(AppIdentifierPrefix)io.esimplified.esimpulse.shared` in their
  entitlements. With a single shared group listed, the app's writes land in that
  group and the widget reads them — no team-prefix hardcoding, and
  `KeychainCredentialStore` is unchanged (it specifies no explicit access group,
  so add uses the entitlement's group and search spans it).
- Both targets are sandboxed (`app-sandbox`) with `network.client`.

## Widget states

- **revenue:** number + delta (+ sparkline on medium).
- **needsAuth:** "Open eSim Pulse to sign in" (no/expired token — widgets can't
  present a login UI). Triggered by missing token or `StatsError.authExpired`.
- **unavailable:** "No data" (transport/other failure).

## Engine change (additive)

- `DashboardStats.deltaPercent: Decimal?` extracted so both the app's
  `DashboardViewModel` and the widget compute the delta one way. Behavior
  identical; all 15 existing tests still pass.

## Targets / files

- New target `eSimPulseWidgetExtension` (`com.apple.product-type.app-extension`,
  bundle id `io.esimplified.esimpulse.widget`), embedded into the app via an
  "Embed App Extensions" copy-files phase + target dependency; links `EsimPulseKit`.
- `eSimPulseWidget/`: `eSimPulseWidgetBundle.swift` (@main `WidgetBundle`),
  `RevenueProvider.swift` (provider + entry + content enum),
  `RevenueWidgetView.swift` (small/medium views + `Sparkline`), `Info.plist`
  (NSExtension widgetkit), `eSimPulseWidget.entitlements`.

## Out of scope (later)

- Configurable currency symbol / refresh interval (Phase 3).
- App Intent configuration (e.g. choosing a metric) — static config for now.
- Today's order count (Phase 2 of the app).

## Signing note

The shared-Keychain capability requires a provisioning profile, so this Mac must
be registered in the developer account (one-time, via Xcode's Signing &
Capabilities tab) before a signed build/run. The code compiles independently of
signing (verified with `CODE_SIGNING_ALLOWED=NO`).
