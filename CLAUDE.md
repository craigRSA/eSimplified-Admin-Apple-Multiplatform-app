# eSim Pulse

A native macOS app + **desktop widget** that show **today's consolidated eSimplified
revenue** at a glance, refreshing automatically. Read-only client of the existing
eSimplified backend — it makes no writes and requires no backend changes.

Two surfaces over the same engine (`EsimPulseKit`): a floating app window, and a
WidgetKit widget (small + medium) addable to the Desktop / Notification Center.

## What it does

Reproduces this query as a glanceable number, plus a delta vs yesterday:

```sql
SELECT SUM(final_price) FROM public.consolidated_orderhistory_data
WHERE payment_status = 'success'
  AND (schema_name_col <> 'esimplified' OR schema_name_col IS NULL)
  AND purchase_date >= today;
```

It gets this from the existing **Admin Dashboard** endpoint — no SQL or DB
connection in the app:

- `GET {adminHost}/api/statistics/?date_range=last_7_days`
- Auth: `Authorization: Bearer <token>` (scope `statistics:read`)
- Fields used: `revenue_today`, `revenue_yesterday`, `current.revenue_per_date[]`,
  `current.success_orders`
- The endpoint already excludes the `esimplified` schema and filters
  `payment_status='success'`.

## Structure

```
EsimPulseKit/   ← local Swift package: ALL testable logic, CLI-testable via `swift test`
  Credentials / CredentialStore / KeychainCredentialStore
  DashboardStats (tolerant decimal decoding)
  StatisticsClient / LiveStatisticsClient / StatsError / DateRange
  DashboardViewModel (@Observable state machine)
eSimPulse/      ← SwiftUI macOS app target (floating window + views), imports EsimPulseKit
eSimPulseiOS/   ← SwiftUI iOS app target (settings + today preview), imports EsimPulseKit
eSimPulseWidget/← WidgetKit sources (provider + views), shared by the macOS and iOS widget targets
docs/specs/     ← approved designs (app + widget)
docs/plans/     ← implementation plan (executed task-by-task, TDD)
```

Four app/extension targets over one engine: macOS app + macOS widget extension,
iOS app + iOS widget extension. The two widget extensions compile the **same**
`eSimPulseWidget/*.swift` sources; they differ only in entitlements
(`eSimPulseWidget.entitlements` for macOS adds app-sandbox; `Widget-iOS.entitlements`
is keychain-only). `EsimPulseKit` supports `.macOS(.v14)` and `.iOS(.v17)`.

The split is deliberate: logic lives in the package so it has true unit tests
runnable from the command line without opening Xcode; the app and widget targets
are thin UI shells verified by build + manual run.

The **widget** runs its own `TimelineProvider` (~20-min refresh), reads the token
from a shared Keychain access group, and fetches via the same `LiveStatisticsClient`
— so it stays current with the app closed. The app is the companion/config surface
(where you enter host + token) and the required container the widget ships inside.

## Conventions

- **Platform floor macOS 14.0** (`@Observable` macro). Swift tools 5.9+.
- **Money is always `Decimal`** — never `Double`/`Float` for storage or comparison.
- API decimal fields may be JSON **strings** (Django DRF default) **or** numbers —
  `FlexibleDecimal` handles both.
- No third-party dependencies — Foundation / SwiftUI / AppKit / XCTest only.
- The Bearer token + admin host live in the **macOS Keychain**, never in
  `UserDefaults` or plaintext.
- App and widget share the token via a shared Keychain access group
  (`$(AppIdentifierPrefix)io.esimplified.esimpulse.shared`, declared in both
  targets' entitlements). Both targets are sandboxed with `network.client`.
- TDD: write the failing test, see it fail, implement, see it pass, commit.

## Commands

```bash
cd EsimPulseKit && swift test          # run the core unit tests
cd EsimPulseKit && swift build         # compile the package
xcodebuild -project eSimPulse.xcodeproj -scheme eSimPulse build   # build app + embedded widget
```

> The widget builds as part of the `eSimPulse` scheme (embedded via an "Embed App
> Extensions" phase). The shared-Keychain capability requires the build machine to
> be registered in the signing team's developer account.

## Status / roadmap

- **Phase 1 (MVP, done):** today's revenue + delta vs yesterday, Keychain token,
  floating window. Plan: `docs/plans/2026-06-17-esim-pulse-phase1.md`.
- **Desktop widget (done):** WidgetKit small + medium (medium adds the 7-day
  sparkline), self-updating, shared-Keychain token.
  Design: `docs/specs/2026-06-17-esim-pulse-widget-design.md`.
- **iPhone app + widget (done, simulator-verified):** iOS app is a settings
  screen + today preview; the iOS widget reuses the shared widget sources.
  Builds for the iOS Simulator without signing; running on a physical device
  needs the iOS targets signed in Xcode (your Apple ID / device registration).
- **Phase 3:** launch-at-login, configurable refresh interval + currency symbol.

Note: the 7-day sparkline (originally Phase 2) shipped in the widget. Today's
order count remains future work.
