import SwiftUI
import Charts
import EsimplifiedKit

struct DashboardScreen: View {
    let session: Session
    var tenant: String?

    @State private var phase: Phase = .loading
    @State private var range: DashRange = .monthToDate
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.tokenProvider) private var tokenProvider

    /// Cap the column to a comfortable reading measure on wide displays.
    private let readingWidth: CGFloat = 900

    enum Phase { case loading, loaded(AdminDashboardStats), failed(String) }

    var body: some View {
        ScrollView {
            Group {
                switch phase {
                case .loading:
                    LoadingSkeleton()
                case let .failed(message):
                    failedView(message)
                case let .loaded(stats):
                    content(stats)
                }
            }
            .frame(maxWidth: readingWidth)
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .snappy, value: isLoaded)
        }
        .background(AppBackground())
        .navigationTitle("Overview")
        .reload(on: "\(tenant ?? "all")|\(range.rawValue)") { await load() }
        .refreshable { await load() }
        .refreshCommand { Task { await load() } }
        .autoRefresh { await load() }
    }

    /// Drives the phase-change animation without animating between two loaded
    /// payloads (which would re-run chart transitions on every auto-refresh).
    private var isLoaded: Bool { if case .loaded = phase { return true }; return false }

    @ViewBuilder private func failedView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load the dashboard", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await load() } }
                .buttonStyle(.glassProminent)
        }
        .frame(minHeight: 320)
    }

    /// Compact date-range picker that lives on the comparison chart it controls.
    private var rangeMenu: some View {
        Menu {
            Picker("Date range", selection: $range) {
                ForEach(DashRange.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label(range.label, systemImage: "calendar")
                .font(.subheadline).labelStyle(.titleAndIcon)
                .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.xs)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    @ViewBuilder private func content(_ s: AdminDashboardStats) -> some View {
        GlassEffectContainer(spacing: Spacing.lg) {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // Signature: today's gross volume
            HeroCard(today: s.revenueToday, yesterday: s.revenueYesterday,
                     yesterdayToDate: s.revenueYesterdayThroughHour(utcHourNow()),
                     hourlyToday: s.revenuePerHourToday, hourlyYesterday: s.revenuePerHourYesterday,
                     trend: s.current.revenuePerDate)

            // Headline metrics — each tile declares how its value should read.
            MetricGrid(items: [
                .text("Tenants", s.tenants.formatted()),
                .count("Customers", s.customers),
                .count("Successful orders", s.successOrders),
                .money("Revenue (all time)", s.revenue, style: .whole),
                .money("Avg order value", s.averageOrderValue, style: .cents),
                .money("Yesterday", s.revenueYesterday, style: .whole),
                .money("Best day", s.bestDay?.revenue ?? 0, style: .whole, sub: s.bestDay?.date),
                .moneyComparison("This month", s.revenueCurrentMonth, .whole,
                                 delta: AdminDashboardStats.change(s.revenueCurrentMonth, vs: s.revenueLastMonth),
                                 prev: s.revenueLastMonth, subPrefix: "vs last"),
                .moneyComparison("This year", s.revenueThisYear, .whole,
                                 delta: AdminDashboardStats.change(s.revenueThisYear, vs: s.revenueLastYear),
                                 prev: s.revenueLastYear, subPrefix: "vs last yr"),
            ], columns: 3)

            // Selected range vs previous comparable period — the date picker
            // lives on this card because it's what the range controls.
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader("\(range.label) vs previous", eyebrow: "Selected range")
                    Spacer()
                    rangeMenu
                }
                let cur = s.current, prev = s.comparison
                MetricGrid(items: [
                    .moneyComparison("Revenue", cur.revenue, .whole,
                                     delta: AdminDashboardStats.change(cur.revenue, vs: prev.revenue),
                                     prev: prev.revenue),
                    .countComparison("Customers", cur.customers,
                                     delta: AdminDashboardStats.change(Decimal(cur.customers), vs: Decimal(prev.customers)),
                                     prev: prev.customers),
                    .moneyComparison("Avg order value", cur.averageOrderValue, .cents,
                                     delta: AdminDashboardStats.change(cur.averageOrderValue, vs: prev.averageOrderValue),
                                     prev: prev.averageOrderValue),
                    .countComparison("Orders", cur.orders,
                                     delta: AdminDashboardStats.change(Decimal(cur.orders), vs: Decimal(prev.orders)),
                                     prev: prev.orders),
                ])
                if !s.current.revenuePerDate.isEmpty {
                    ComparisonAreaChart(current: s.current.revenuePerDate, previous: s.comparison.revenuePerDate,
                                        monthly: range.isYearScale)
                        .frame(height: 220)
                }
            }
            .glassCard()

            if !s.revenuePerTenant.isEmpty {
                SectionCard(title: "Revenue per tenant") {
                    RevenueBarChart(items: Array(s.revenuePerTenant.prefix(8)).map { ($0.tenant, $0.amount) })
                        .frame(height: 240)
                }
            }

            if !s.revenuePerMonth.isEmpty {
                SectionCard(title: "Revenue per month") {
                    RevenueBarChart(items: s.revenuePerMonth.map { (shortMonth($0.month), $0.amount) })
                        .frame(height: 220)
                }
            }

            if !s.current.topPackages.isEmpty || !s.current.topCountries.isEmpty {
                // Side-by-side on regular width; stacked on a phone so each list
                // keeps a readable measure.
                let layout = hSize == .compact
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.lg))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.lg))
                layout {
                    if !s.current.topPackages.isEmpty {
                        SectionCard(title: "Top packages") { TopList(items: s.current.topPackages) }
                    }
                    if !s.current.topCountries.isEmpty {
                        SectionCard(title: "Top countries") { TopList(items: s.current.topCountries) }
                    }
                }
            }
        }
        .padding(Spacing.xl)
        }
    }

    private func load() async {
        do {
            let client = LiveAPIClient(host: session.host, tokenProvider: tokenProvider)
            let path = tenant.map { "/api/statistics/\($0)/" } ?? "/api/statistics/"
            let stats = try await client.get(path, query: ["date_range": range.rawValue], as: AdminDashboardStats.self)
            phase = .loaded(stats)
        } catch let error as APIError {
            phase = .failed(adminErrorMessage(error))
        } catch is CancellationError {
            // View navigated away mid-load — not a real error.
        } catch {
            phase = .failed("Unexpected error.")
        }
    }
}

// MARK: - Loading skeleton

/// Redacted placeholder that mirrors the hero card + metric grid, so a range or
/// tenant change reshapes in place instead of blanking the whole screen.
private struct LoadingSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // Hero
            VStack(alignment: .leading, spacing: Spacing.md) {
                SkeletonBar(width: 160, height: 12)
                SkeletonBar(width: 220, height: 44)
                SkeletonBar(width: 140, height: 14)
                SkeletonBar(height: 110)
            }
            .glassCard(radius: Radius.card, padding: Spacing.xl)

            // Metric grid — mirrors the 3-wide, icon-free stat grid.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 3), spacing: Spacing.md) {
                ForEach(0..<9, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        SkeletonBar(width: 90, height: 20)
                        SkeletonBar(width: 64, height: 12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.md)
                    .glassEffect(.regular, in: .rect(cornerRadius: Radius.chip))
                }
            }
        }
        .padding(Spacing.xl)
        .accessibilityElement()
        .accessibilityLabel("Loading dashboard")
    }
}

// utcHourNow() / utcHourFractionNow() now live in EsimplifiedKit (HourlyRevenue.swift),
// shared with the widget and menu bar so the UTC "to date" reckoning can't drift.

// MARK: - Building blocks

/// The hero: today's gross volume, the day's delta, and — when the backend
/// provides hourly data — the cumulative today-vs-yesterday curve.
private struct HeroCard: View {
    let today: Decimal
    let yesterday: Decimal
    /// Yesterday's revenue through the current point in the day (UTC); nil pre-hourly.
    let yesterdayToDate: Decimal?
    let hourlyToday: [HourPoint]
    let hourlyYesterday: [HourPoint]
    let trend: [DayRevenue]

    /// Compare today-so-far against yesterday "to date" (same point in the day) when
    /// hourly data exists; otherwise the full prior day — the pre-hourly fallback.
    private var comparisonBase: Decimal { yesterdayToDate ?? yesterday }
    private var deltaCaption: String {
        // "(to date)" = compared against yesterday cumulative through this same point
        // in the day. Without hourly data we fall back to the full-day comparison.
        yesterdayToDate != nil ? "vs yesterday (to date)" : "vs yesterday"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Hero eyebrow (the big number below is the headline, drawn at hero scale).
            Eyebrow("Today's gross volume")
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                Text(Fmt.money(today, style: .whole))
                    .font(Font.display(.largeTitle)).monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .accessibilityLabel("Today's gross volume: \(Fmt.money(today, style: .whole))")
                TrendDelta(percent: AdminDashboardStats.change(today, vs: comparisonBase), pill: true)
            }
            Text(deltaCaption)
                .font(.subheadline).foregroundStyle(.secondary)

            if hourlyToday.count > 1 || hourlyYesterday.count > 1 {
                // Show the intraday chart whenever either day has data — so before
                // today's first sale you still see yesterday's curve.
                HourlyComparisonChart(today: hourlyToday, yesterday: hourlyYesterday)
                    .frame(height: 120).padding(.top, Spacing.xs)
            } else if trend.count > 2 {
                // Fallback until hourly data ships: the recent daily trend. Drop the
                // last point — it's the in-progress UTC day, so it nosedives to ~0.
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Sparkline(points: trend.dropLast().map { dbl($0.revenue) }).frame(height: 54)
                        .accessibilityElement()
                        .accessibilityLabel("Daily revenue trend over completed days")
                    Eyebrow("Daily trend · completed days")
                }
                .padding(.top, Spacing.xs)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.card))
    }
}

/// A standalone eyebrow overline, matching `SectionHeader`'s eyebrow register —
/// used where the headline is rendered separately at a larger scale (the hero
/// figure, the sparkline) so a full `SectionHeader` title would duplicate it.
/// Defined once here so both the hero and the daily-trend overline share one
/// consistent eyebrow, replacing the hand-typed `.caption`/`.caption2` +
/// `tracking` variants this file used before.
private struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).eyebrow()
    }
}

/// Cumulative sales through the day (UTC) — today solid, yesterday dashed.
/// Backend sends per-hour increments; we accumulate them into a running total
/// and plot at the end of each hour (hour 0 → the `1` mark), with a 0 start so
/// a single hour still draws a line up to its value.
/// Cumulative today-vs-yesterday sales curve. Shared by the dashboard hero and the
/// macOS menu-bar panel; the cumulative points come from EsimplifiedKit's
/// `cumulativeHourly` so the curve matches the widget too.
struct HourlyComparisonChart: View {
    let today: [HourPoint]
    let yesterday: [HourPoint]
    @State private var selectedX: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Today's line stops at the elapsed fraction of the current UTC hour (08:30 →
        // 8.5); yesterday is a complete day, so it draws across the full axis.
        let t = cumulativeHourly(today, cappedAt: utcHourFractionNow())
        let y = cumulativeHourly(yesterday)
        Chart {
            ForEach(y, id: \.hour) { p in
                LineMark(x: .value("Hour", p.hour), y: .value("Sales", p.total),
                         series: .value("Day", "Yesterday"))
                    .foregroundStyle(.gray)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }
            ForEach(t, id: \.hour) { p in
                LineMark(x: .value("Hour", p.hour), y: .value("Sales", p.total),
                         series: .value("Day", "Today"))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            if let selectedX {
                RuleMark(x: .value("Hour", selectedX))
                    .foregroundStyle(Color.secondary.opacity(0.25))
                    .accessibilityHidden(true)
                    .annotation(position: .top, spacing: 0,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartTooltip(title: String(format: "%02d:00", min(max(Int(selectedX.rounded()), 0), 24)), rows: [
                            ("Today", Fmt.money(Decimal(Self.valueAt(t, selectedX)), style: .whole), .accentColor),
                            ("Yesterday", Fmt.money(Decimal(Self.valueAt(y, selectedX)), style: .whole), .gray),
                        ])
                    }
            }
        }
        .chartForegroundStyleScale(["Today": Color.accentColor, "Yesterday": Color.gray])
        .chartXScale(domain: 0.0...24.0)
        .chartXAxis { AxisMarks(values: [0.0, 6.0, 12.0, 18.0, 24.0]) { v in
            AxisGridLine()
            AxisValueLabel { if let h = v.as(Double.self) { Text(String(format: "%02d:00", Int(h))) } }
        } }
        .chartXSelection(value: $selectedX)
        .animation(reduceMotion ? nil : .snappy, value: selectedX)
        .chartLegend(position: .top, alignment: .leading, spacing: Spacing.sm)
        .accessibilityElement()
        .accessibilityLabel("Cumulative sales today versus yesterday")
        .accessibilityValue(
            "Today \(Fmt.money(Decimal(Self.valueAt(t, 24)), style: .whole)), yesterday \(Fmt.money(Decimal(Self.valueAt(y, 24)), style: .whole))"
        )
    }

    /// Cumulative value at or before the selected hour mark.
    static func valueAt(_ pts: [CumulativeHourPoint], _ x: Double) -> Double {
        pts.last(where: { $0.hour <= x })?.total ?? 0
    }
}

/// Small floating tooltip shown when a chart point is selected.
struct ChartTooltip: View {
    let title: String
    let rows: [(String, String, Color)]
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).font(.caption2.weight(.semibold))
            ForEach(rows, id: \.0) { row in
                HStack(spacing: Spacing.xs) {
                    if !row.0.isEmpty {
                        Circle().fill(row.2).frame(width: 6, height: 6)
                        Text(row.0).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(row.1).font(.caption2.monospacedDigit())
                }
            }
        }
        .padding(Spacing.sm)
        .background(.regularMaterial, in: .rect(cornerRadius: Radius.tooltip))
        .shadow(radius: 3, y: 1)
    }
}


/// A minimal filled area sparkline — no axes, just the shape of the trend.
private struct Sparkline: View {
    let points: [Double]
    var body: some View {
        Chart(Array(points.enumerated()), id: \.offset) { i, v in
            AreaMark(x: .value("i", i), y: .value("v", v))
                .foregroundStyle(.linearGradient(
                    colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("i", i), y: .value("v", v))
                .foregroundStyle(Color.accentColor).lineStyle(.init(lineWidth: 2))
                .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden).chartYAxis(.hidden)
    }
}

private struct MetricItem: Identifiable {
    let id = UUID()
    let title: String
    let displayValue: String
    let delta: Decimal?
    let sub: String?

    static func text(_ title: String, _ value: String) -> MetricItem {
        MetricItem(title: title, displayValue: value)
    }

    static func count(_ title: String, _ value: Int) -> MetricItem {
        MetricItem(title: title, displayValue: Fmt.count(value))
    }

    static func money(_ title: String, _ value: Decimal, style: Fmt.MoneyStyle, sub: String? = nil) -> MetricItem {
        MetricItem(title: title, displayValue: Fmt.money(value, style: style), sub: sub)
    }

    static func moneyComparison(_ title: String, _ value: Decimal, _ style: Fmt.MoneyStyle,
                                delta: Decimal?, prev: Decimal, subPrefix: String = "Prev") -> MetricItem {
        MetricItem(title: title, displayValue: Fmt.money(value, style: style), delta: delta,
                   sub: "\(subPrefix): \(Fmt.money(prev, style: style))")
    }

    static func countComparison(_ title: String, _ value: Int, delta: Decimal?, prev: Int) -> MetricItem {
        MetricItem(title: title, displayValue: Fmt.count(value), delta: delta,
                   sub: "Prev: \(Fmt.count(prev))")
    }

    private init(title: String, displayValue: String, delta: Decimal? = nil, sub: String? = nil) {
        self.title = title; self.displayValue = displayValue; self.delta = delta; self.sub = sub
    }
}

private struct MetricGrid: View {
    let items: [MetricItem]
    /// Fixed column count for a balanced grid (e.g. 3 → the 9 top stats fill 3×3 with
    /// no orphan); nil keeps the responsive adaptive layout.
    var columns: Int?
    @Environment(\.horizontalSizeClass) private var hSize

    private var gridColumns: [GridItem] {
        if let columns {
            return Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: columns)
        }
        return [GridItem(.adaptive(minimum: 165), spacing: Spacing.md)]
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: Spacing.md) {
            ForEach(items) { item in
                // Match the hero: eyebrow label on top, then the value with its delta
                // inline beside it, then the optional context line — no 4-line stack.
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(item.title.uppercased()).eyebrow()
                    // Inline value + delta on wide cards; stacked on a phone, where a
                    // 3-wide card can't fit both on one line without truncating.
                    let valueDelta = hSize == .compact
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.sm))
                    valueDelta {
                        Text(item.displayValue).font(.title3.weight(.semibold).monospacedDigit())
                            .lineLimit(1).minimumScaleFactor(0.55)
                        if let delta = item.delta {
                            TrendDelta(percent: delta, font: .caption.weight(.semibold)).fixedSize()
                        }
                    }
                    if let sub = item.sub { Text(sub).font(.caption2).foregroundStyle(.secondary) }
                }
                // maxHeight makes cards in a row share a height, so the grid reads as
                // even tiles instead of ragged ones.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(Spacing.md)
                .glassEffect(.regular, in: .rect(cornerRadius: Radius.chip))
            }
        }
    }
}

private struct ComparisonAreaChart: View {
    let current: [DayRevenue]
    let previous: [DayRevenue]
    /// Year-to-date data is monthly — label the x-axis by month instead of by
    /// day index.
    var monthly: Bool = false
    @State private var selected: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func label(_ i: Int) -> String {
        monthly && current.indices.contains(i) ? shortMonth(current[i].date) : "Day \(i + 1)"
    }

    var body: some View {
        Chart {
            ForEach(Array(current.enumerated()), id: \.offset) { i, day in
                AreaMark(x: .value("Point", i), y: .value("Revenue", dbl(day.revenue)),
                         series: .value("Period", "This period"))
                    .foregroundStyle(.linearGradient(colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.02)],
                                                     startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Point", i), y: .value("Revenue", dbl(day.revenue)),
                         series: .value("Period", "This period"))
                    .foregroundStyle(Color.accentColor).interpolationMethod(.catmullRom)
            }
            ForEach(Array(previous.enumerated()), id: \.offset) { i, day in
                LineMark(x: .value("Point", i), y: .value("Revenue", dbl(day.revenue)),
                         series: .value("Period", "Previous"))
                    .foregroundStyle(.gray).interpolationMethod(.catmullRom)
            }
            if let selected, current.indices.contains(selected) {
                RuleMark(x: .value("Point", selected))
                    .foregroundStyle(Color.secondary.opacity(0.25))
                    .accessibilityHidden(true)
                    .annotation(position: .top, spacing: 0,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartTooltip(title: label(selected), rows: [
                            ("This", Fmt.money(current[selected].revenue, style: .whole), .accentColor),
                            ("Prev", Fmt.money(previous.indices.contains(selected) ? previous[selected].revenue : 0, style: .whole), .gray),
                        ])
                    }
            }
        }
        .chartForegroundStyleScale(["This period": Color.accentColor, "Previous": Color.gray])
        .chartXSelection(value: $selected)
        .animation(reduceMotion ? nil : .snappy, value: selected)
        .chartXAxis {
            if monthly {
                AxisMarks(values: tickIndices(count: current.count, desired: 6)) { value in
                    if let i = value.as(Int.self), current.indices.contains(i) {
                        AxisValueLabel { Text(shortMonth(current[i].date)) }
                    }
                }
            } else {
                AxisMarks(values: .automatic(desiredCount: 5))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("This period versus the previous comparable period")
        .accessibilityValue(
            "This period total \(Fmt.money(current.reduce(Decimal(0)) { $0 + $1.revenue }, style: .whole)), "
            + "previous \(Fmt.money(previous.reduce(Decimal(0)) { $0 + $1.revenue }, style: .whole))"
        )
    }
}

private struct RevenueBarChart: View {
    let items: [(String, Decimal)]
    @State private var selected: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Chart {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                // A categorical x gives each bar a full, centered slot (the old index
                // axis drew thin slivers and clipped the first bar at the edge).
                BarMark(x: .value("Name", item.0), y: .value("Revenue", dbl(item.1)))
                    .foregroundStyle(Color.accentColor.opacity(selected == nil || selected == item.0 ? 1 : 0.4))
                    .annotation(position: .top, spacing: 2) {
                        // Value on top so short bars stay legible; skipped once there
                        // are enough bars (the monthly chart) that labels would collide.
                        if items.count <= 8 {
                            Text(Fmt.money(item.1, style: .whole)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
            }
            if let selected, let value = items.first(where: { $0.0 == selected })?.1 {
                RuleMark(x: .value("Name", selected))
                    .foregroundStyle(.clear)
                    .accessibilityHidden(true)
                    .annotation(position: .top, spacing: 0,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartTooltip(title: selected, rows: [("", Fmt.money(value, style: .whole), .accentColor)])
                    }
            }
        }
        .chartXSelection(value: $selected)
        .animation(reduceMotion ? nil : .snappy, value: selected)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel(orientation: .verticalReversed) {
                    if let name = value.as(String.self) { Text(name) }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Revenue by category")
        .accessibilityValue(axSummary)
    }

    /// Names the top entries so VoiceOver conveys the chart without the visual bars.
    private var axSummary: String {
        items.prefix(3)
            .map { "\($0.0) \(Fmt.money($0.1, style: .whole))" }
            .joined(separator: ", ")
    }
}

/// Evenly-spaced 0-based indices for axis ticks, so charts don't crowd labels.
private func tickIndices(count: Int, desired: Int) -> [Int] {
    guard count > desired, desired > 0 else { return Array(0..<max(count, 0)) }
    let step = max(1, Int((Double(count) / Double(desired)).rounded(.up)))
    return Array(stride(from: 0, to: count, by: step))
}

/// "2026-03-01" / "2026-03" → "Mar".
private func shortMonth(_ date: String) -> String {
    let parts = date.split(separator: "-")
    guard parts.count >= 2, let m = Int(parts[1]), (1...12).contains(m) else { return "" }
    return ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][m - 1]
}

private struct TopList: View {
    let items: [LabeledCount]
    var body: some View {
        let maxCount = max(items.map(\.count).max() ?? 1, 1)
        VStack(spacing: Spacing.sm) {
            ForEach(items.prefix(5)) { item in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        Text(item.label).font(.caption).lineLimit(1)
                        Spacer()
                        Text(item.count.formatted()).font(.caption.monospacedDigit().weight(.semibold))
                    }
                    GeometryReader { geo in
                        Capsule().fill(Color.accentColor.opacity(0.25))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color.accentColor)
                                    .frame(width: geo.size.width * CGFloat(item.count) / CGFloat(maxCount))
                            }
                    }
                    .frame(height: 5)
                    .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.label): \(item.count.formatted())")
            }
        }
    }
}

/// Dashboard date-range options (sent as `?date_range=`), in the web's display
/// order. All values except `year_to_date` are live on the backend today;
/// `year_to_date` is a documented pending addition
/// (docs/backend/2026-06-19-statistics-hourly-and-ytd.md) that no-ops until the
/// backend ships it. Raw values must match the web's `date_range` strings exactly.
enum DashRange: String, CaseIterable, Identifiable {
    case today
    case thisWeek = "this_week"
    case thisMonth = "this_month"
    case lastMonth = "last_month"
    case monthToDate = "month_to_date"
    case last7 = "last_7_days"
    case last30 = "last_30_days"
    case thisYear = "this_year"
    case yearToDate = "year_to_date"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .today: "Today"
        case .thisWeek: "This Week"
        case .thisMonth: "This Month"
        case .lastMonth: "Last Month"
        case .monthToDate: "Month to Date"
        case .last7: "Last 7 Days"
        case .last30: "Last 30 Days"
        case .thisYear: "This Year"
        case .yearToDate: "Year to Date"
        }
    }

    /// Year-scale ranges whose comparison chart reads better with month labels
    /// than day-index labels.
    var isYearScale: Bool { self == .thisYear || self == .yearToDate }
}

// Fmt + dbl now live in AdminTheme.swift (shared formatting helpers).
