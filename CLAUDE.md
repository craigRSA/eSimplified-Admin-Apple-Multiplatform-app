# eSim Pulse

A native macOS desktop window that shows **today's consolidated eSimplified revenue**
at a glance, refreshing automatically. Read-only client of the existing eSimplified
backend — it makes no writes and requires no backend changes.

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

- `GET {adminHost}/api/v1/statistics/?date_range=last_7_days`
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
eSimPulse/      ← thin SwiftUI macOS app target (window + views), imports EsimPulseKit
docs/specs/     ← approved design
docs/plans/     ← implementation plan (executed task-by-task, TDD)
```

The split is deliberate: logic lives in the package so it has true unit tests
runnable from the command line without opening Xcode; the app target is a thin
UI shell verified by build + manual run.

## Conventions

- **Platform floor macOS 14.0** (`@Observable` macro). Swift tools 5.9+.
- **Money is always `Decimal`** — never `Double`/`Float` for storage or comparison.
- API decimal fields may be JSON **strings** (Django DRF default) **or** numbers —
  `FlexibleDecimal` handles both.
- No third-party dependencies — Foundation / SwiftUI / AppKit / XCTest only.
- The Bearer token + admin host live in the **macOS Keychain**, never in
  `UserDefaults` or plaintext.
- TDD: write the failing test, see it fail, implement, see it pass, commit.

## Commands

```bash
cd EsimPulseKit && swift test          # run the core unit tests
cd EsimPulseKit && swift build         # compile the package
xcodebuild -project eSimPulse.xcodeproj -scheme eSimPulse build   # build the app
```

## Status / roadmap

- **Phase 1 (MVP, current):** today's revenue + delta vs yesterday, Keychain
  token, floating window. Plan: `docs/plans/2026-06-17-esim-pulse-phase1.md`.
- **Phase 2:** 7-day sparkline (Swift Charts) + today's order count.
- **Phase 3:** launch-at-login, configurable refresh interval + currency symbol.
