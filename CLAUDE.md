# eSimplified

This repo holds two native Apple products over one shared engine (`EsimplifiedKit`):

1. **eSimplified** — a glanceable view of **today's consolidated eSimplified
   revenue** (number + delta vs yesterday + 7-day trend), as a multiplatform app
   (macOS floating window / iOS screen) plus a WidgetKit widget. Read-only.
2. **eSimplified Admin** — a native (Mac/iPad/iPhone) reimplementation of a curated
   subset of the web admin front end (in progress).

Both are read-mostly clients of the existing eSimplified backend — no backend changes.

> Folder/scheme note: the historical names live on in a few places — the git repo
> directory is still `eSimPulse/` and some older docs/plans say "eSim Pulse". The
> Xcode project is `Esimplified.xcodeproj`; the glance app/target is `Esimplified`.

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
EsimplifiedKit/   ← local Swift package: ALL testable logic, CLI-testable via `swift test`
  Credentials / CredentialStore / KeychainCredentialStore
  DashboardStats (tolerant decimal decoding)
  StatisticsClient / LiveStatisticsClient / StatsError / DateRange
  DashboardViewModel (@Observable state machine)
Esimplified/      ← ONE multiplatform SwiftUI app target (macOS + iPadOS + iOS), imports EsimplifiedKit
EsimplifiedWidget/← ONE multiplatform WidgetKit extension, embedded in the app
docs/specs/       ← approved designs (app + widget)
docs/plans/       ← implementation plans (executed task-by-task, TDD)
```

Two targets over one engine: the **Esimplified** app (Supported Destinations =
Mac + iPhone + iPad; adaptive UI — `MacViews.swift` floating window on macOS,
`PhoneViews.swift` on iOS, `RevenueViews.swift` shared) and the **EsimplifiedWidget**
extension (embedded in the app, same sources on every platform). `EsimplifiedKit`
supports `.macOS(.v14)` and `.iOS(.v17)`.

The split is deliberate: logic lives in the package so it has true unit tests
runnable from the command line without opening Xcode; the app and widget targets
are thin UI shells verified by build + manual run.

> A second product, **eSimplified Admin** (the native admin app), is being built
> in `EsimplifiedAdmin/` over the same `EsimplifiedKit` engine. Design:
> `docs/specs/2026-06-19-esimplified-admin-native-design.md`.

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
  (`$(AppIdentifierPrefix)io.esimplified.glance.shared`, declared in both
  targets' entitlements). Both targets are sandboxed with `network.client`.
  App bundle id `io.esimplified.glance`; widget `io.esimplified.glance.widget`.
- TDD: write the failing test, see it fail, implement, see it pass, commit.

## Commands

```bash
cd EsimplifiedKit && swift test          # run the core unit tests
cd EsimplifiedKit && swift build         # compile the package
xcodebuild -project Esimplified.xcodeproj -scheme Esimplified build   # build app + embedded widget
```

> The widget builds as part of the `Esimplified` scheme (embedded via an "Embed App
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
