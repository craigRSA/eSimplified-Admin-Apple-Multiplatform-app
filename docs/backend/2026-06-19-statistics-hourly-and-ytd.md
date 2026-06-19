# Frontend Handoff — `/api/statistics/` additions (YTD + hourly)

Two **additive, read-only** changes. No existing field changed shape.

Endpoint unchanged: `GET /api/statistics/` and `GET /api/statistics/{tenant}/`,
`Authorization: Bearer <token>`, scope `statistics:read`.

## 1. New `date_range` value: `year_to_date`

Accepted alongside the existing values. Same response shape as `month_to_date`,
at year scale:

- `current` = **Jan 1 of this year → today** (inclusive)
- `comparison` = **Jan 1 last year → the same month/day last year**

Both buckets carry the same fields they already do (`revenue`,
`average_order_value`, `customers`, `orders`, `revenue_per_date`, `top_packages`,
`top_countries`). `revenue_per_date` is **daily** (consistent with `this_year`).

Use it for the "Year to date vs previous" card, exactly like the existing
"Month to date vs previous" one.

## 2. Hourly series — two new **top-level** fields (always present)

`revenue_per_hour_today` and `revenue_per_hour_yesterday` are returned on
**every** response (like `revenue_today` / `revenue_yesterday`) — **not** gated
behind any `date_range` and **no extra param**.

```jsonc
{
  // ...existing top-level fields unchanged...
  "revenue_today": 305.50,
  "revenue_yesterday": 410.00,
  "revenue_per_hour_today": [
    { "hour": 0,  "revenue": 120.00 },
    { "hour": 1,  "revenue": 0.00 },
    // ... up to the current hour
    { "hour": 14, "revenue": 305.50 }
  ],
  "revenue_per_hour_yesterday": [
    { "hour": 0,  "revenue": 95.00 },
    // ... up to the SAME current hour
    { "hour": 14, "revenue": 280.00 }
  ]
}
```

Rules:
- **`hour`** is `0–23`, integer, **UTC** — the same timezone that defines "today"
  everywhere else in this response.
- **Both arrays run `0 → current hour`** (up to now). No future hours. Yesterday is
  truncated to the same current hour so it's an apples-to-apples "yesterday at this
  time" comparison (it is **not** the full 0–23 day).
- **Per-hour increments**, not cumulative — accumulate client-side for the cumulative
  curve (today solid, yesterday dashed).
- **USD** (`final_price`), same filters as the headline revenue.
- **Reconciliation:** the sum of `revenue_per_hour_today` equals `revenue_today`.
  (The yesterday array sums to *partial* yesterday up to the current hour, by design —
  so it will be less than the full-day `revenue_yesterday`.)
- **Tenant scoping** respects the `{tenant}` path segment like everything else.
- Revenue values serialize the same way the existing `revenue_*` fields do (treat them
  identically to `revenue_today`).

## Client plan (unchanged from your note)

`date_range` dropdown: `today`, `month_to_date`, `year_to_date`, etc. The
hourly today-vs-yesterday cumulative chart reads the two top-level arrays (no
dependence on the selected `date_range`); `month_to_date` / `year_to_date`
render the "X to date vs previous" comparison card. One endpoint, no extra calls.
