# eSim Pulse — macOS Revenue Dashboard

**Date:** 2026-06-17
**Status:** Design approved, pre-implementation
**Location:** `~/xcode/eSimPulse` (standalone Xcode project, alongside `~/xcode/iOS-knowroaming`)

## Purpose

A small always-on-top macOS desktop window that displays today's consolidated
revenue at a glance, refreshing automatically. It is a **read-only client** of
the existing eSimplified backend — no backend changes are required.

The headline number reproduces this query:

```sql
SELECT SUM(final_price) AS sum
FROM public.consolidated_orderhistory_data
WHERE payment_status = 'success'
  AND (schema_name_col <> 'esimplified' OR schema_name_col IS NULL)
  AND purchase_date >= CAST(CAST(NOW() AS date) AS timestamptz)
  AND purchase_date <  CAST(CAST((NOW() + INTERVAL '1 day') AS date) AS timestamptz);
```

## Data Source

Reuses the existing **Admin Dashboard Statistics** endpoint — no new endpoint.

- **Request:** `GET {adminHost}/api/v1/statistics/?date_range=last_7_days`
- **Auth:** `Authorization: Bearer <token>` (OAuth2; endpoint also has a Basic-Auth fallback we are not using)
- **Scope:** `statistics:read`
- **View:** `api_admin/views.py:852` `DashboardDataAPI`
- **URL:** `api_admin/urls.py:127`

The endpoint already excludes the internal `esimplified` schema by default and
filters `payment_status='success'`, matching the SQL above.

### Fields consumed (subset of the response)

| Field | Source in response | Used for |
| --- | --- | --- |
| `revenue_today` | top-level | Headline number |
| `revenue_yesterday` | top-level | Delta vs yesterday |
| `current.revenue_per_date[]` | `{date, revenue}` array | 7-day sparkline |
| `current.success_orders` | nested (with `?date_range=today`) | Today's order count (Phase 2) |

A single `?date_range=last_7_days` request yields the headline, the delta, and
the sparkline. Today's order count requires a second `?date_range=today`
request and is deferred to Phase 2.

## Authentication

**Stored Bearer token.** The user pastes a long-lived access token into the
Settings sheet. The token and the admin host base URL are persisted in the
**macOS Keychain** (never in `UserDefaults` or plaintext on disk). On a `401`
the UI prompts the user to re-paste the token.

## Architecture

Four small, independently-testable units.

### 1. `KeychainStore`
Saves/loads `adminHost: String` and `bearerToken: String`. Thin wrapper over
the Keychain Services API. Round-trip unit-tested.

### 2. `StatisticsClient`
One async function: `fetch(dateRange:) async throws -> DashboardStats`.

- Builds `GET {host}/api/v1/statistics/?date_range=<range>` with the Bearer header.
- Decodes JSON into a typed `DashboardStats` struct (only the fields above).
- Error mapping: `401 → StatsError.authExpired`, transport failure →
  `StatsError.unreachable`, malformed/empty body → `StatsError.noData`.
- Decoding tested against a saved JSON fixture of a real response.

### 3. `DashboardViewModel`
`@Observable`. Holds `State { loading, loaded(DashboardStats), error(StatsError) }`.
Owns a refresh `Timer` (default 60s) and exposes `refresh()` for the manual
button. On transport failure it keeps the last good `loaded` value and flags it
stale rather than discarding it. State transitions tested with a mock client.

### 4. `DashboardView` + `SettingsView`
SwiftUI. Compact always-on-top floating window (`NSWindow.level = .floating`,
fixed ~280×200). `SettingsView` is a sheet for host + token entry.

## Data Flow

```
Timer (60s) / manual refresh button
  → DashboardViewModel.refresh()
    → StatisticsClient.fetch(.last7Days)
      → decode → State = .loaded(stats)  (or .error)
        → DashboardView re-renders
```

## UI

- **Headline:** `revenue_today`, formatted with a configurable currency symbol
  from Settings. Note: the endpoint sums `final_price` across all tenants
  regardless of each tenant's own currency — this is a raw consolidated figure,
  identical to the source SQL. The symbol is cosmetic.
- **Delta:** `▲ 12%` (green) / `▼ 5%` (red) vs `revenue_yesterday`.
- **Sparkline:** 7-day trend via Swift Charts from `current.revenue_per_date`.
- **Footer:** last-updated timestamp + manual refresh button.
- **Auth-expired state:** body replaced with "Token expired — update in Settings."
- **Stale state:** last good numbers shown with a dim "stale" indicator dot.

## Error Handling

| Condition | Behavior |
| --- | --- |
| No network / timeout | Keep last good numbers, show stale dot |
| `401` | Replace body with "Token expired — update in Settings" |
| Malformed / empty JSON | Show "No data" |

## Phasing

- **Phase 1 (MVP):** `KeychainStore` + `StatisticsClient` + `DashboardViewModel`
  + window showing today's revenue and the delta vs yesterday. Goal: on screen
  and authenticating against the real endpoint.
- **Phase 2:** 7-day sparkline (Swift Charts) + today's order count (second
  `?date_range=today` call).
- **Phase 3:** launch-at-login, configurable refresh interval, configurable
  currency symbol.

## Testing

- `StatisticsClient` decoding against a saved JSON fixture.
- `DashboardViewModel` state transitions with a mock client.
- `KeychainStore` save/load round-trip.

## Out of Scope

- No write operations of any kind.
- No multi-account / multi-host switching (single host + token).
- No menu-bar presence (desktop window only).
- Per-tenant or per-currency breakdowns.
