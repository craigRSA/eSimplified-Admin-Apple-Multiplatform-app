import SwiftUI
import Charts
import EsimplifiedKit

struct DashboardScreen: View {
    let session: Session
    var tenant: String?

    @State private var phase: Phase = .loading
    @State private var range: DashRange = .monthToDate

    enum Phase { case loading, loaded(AdminDashboardStats), failed(String) }

    var body: some View {
        ScrollView {
            switch phase {
            case .loading:
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, minHeight: 320)
            case let .failed(message):
                ContentUnavailableView("Couldn't load the dashboard", systemImage: "exclamationmark.triangle",
                                       description: Text(message)).frame(minHeight: 320)
            case let .loaded(stats):
                content(stats)
            }
        }
        .background(AppBackground())
        .navigationTitle("Overview")
        .reload(on: "\(tenant ?? "all")|\(range.rawValue)") { await load() }
        .refreshable { await load() }
        .autoRefresh { await load() }
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
                .padding(.horizontal, 10).padding(.vertical, 5)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    @ViewBuilder private func content(_ s: AdminDashboardStats) -> some View {
        GlassEffectContainer(spacing: 16) {
        VStack(alignment: .leading, spacing: 22) {
            // Signature: today's gross volume
            HeroCard(today: s.revenueToday, yesterday: s.revenueYesterday,
                     hourlyToday: s.revenuePerHourToday, hourlyYesterday: s.revenuePerHourYesterday,
                     trend: s.current.revenuePerDate)

            // Headline metrics
            MetricGrid(items: [
                .init("Tenants", s.tenants.formatted(), "building.2", .purple),
                .init("Customers", Fmt.countCompact(s.customers), "person.2", .orange),
                .init("Successful orders", Fmt.countCompact(s.successOrders), "checkmark.seal", .green),
                .init("Revenue (all time)", Fmt.money(s.revenue), "dollarsign.circle", .green),
                .init("Avg order value", Fmt.money(s.averageOrderValue), "cart", .pink),
                .init("Best day", Fmt.money(s.bestDay?.revenue ?? 0), "trophy", .yellow),
                .comparison("This month", Fmt.money(s.revenueCurrentMonth),
                            AdminDashboardStats.change(s.revenueCurrentMonth, vs: s.revenueLastMonth),
                            "vs last: \(Fmt.money(s.revenueLastMonth))"),
                .comparison("This year", Fmt.money(s.revenueThisYear),
                            AdminDashboardStats.change(s.revenueThisYear, vs: s.revenueLastYear),
                            "vs last yr: \(Fmt.money(s.revenueLastYear))"),
            ])

            // Selected range vs previous comparable period — the date picker
            // lives on this card because it's what the range controls.
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(range.label) vs previous").font(.headline)
                    Spacer()
                    rangeMenu
                }
                let cur = s.current, prev = s.comparison
                MetricGrid(items: [
                    .comparison("Revenue", Fmt.money(cur.revenue), AdminDashboardStats.change(cur.revenue, vs: prev.revenue), "Prev: \(Fmt.money(prev.revenue))"),
                    .comparison("Customers", Fmt.countCompact(cur.customers), AdminDashboardStats.change(Decimal(cur.customers), vs: Decimal(prev.customers)), "Prev: \(Fmt.countCompact(prev.customers))"),
                    .comparison("Avg order value", Fmt.money(cur.averageOrderValue), AdminDashboardStats.change(cur.averageOrderValue, vs: prev.averageOrderValue), "Prev: \(Fmt.money(prev.averageOrderValue))"),
                    .comparison("Orders", Fmt.countCompact(cur.orders), AdminDashboardStats.change(Decimal(cur.orders), vs: Decimal(prev.orders)), "Prev: \(Fmt.countCompact(prev.orders))"),
                ])
                if !s.current.revenuePerDate.isEmpty {
                    ComparisonAreaChart(current: s.current.revenuePerDate, previous: s.comparison.revenuePerDate,
                                        monthly: range == .yearToDate)
                        .frame(height: 220)
                }
            }
            .glassCard()

            if !s.revenuePerTenant.isEmpty {
                Card(title: "Revenue per tenant") {
                    RevenueBarChart(items: Array(s.revenuePerTenant.prefix(8)).map { ($0.tenant, $0.amount) })
                        .frame(height: 240)
                }
            }

            if !s.revenuePerMonth.isEmpty {
                Card(title: "Revenue per month") {
                    RevenueBarChart(items: s.revenuePerMonth.map { (shortMonth($0.month), $0.amount) },
                                    desiredLabels: 6)
                        .frame(height: 220)
                }
            }

            if !s.current.topPackages.isEmpty || !s.current.topCountries.isEmpty {
                HStack(alignment: .top, spacing: 16) {
                    if !s.current.topPackages.isEmpty {
                        Card(title: "Top packages") { TopList(items: s.current.topPackages) }
                    }
                    if !s.current.topCountries.isEmpty {
                        Card(title: "Top countries") { TopList(items: s.current.topCountries) }
                    }
                }
            }
        }
        .padding(20)
        }
    }

    private func load() async {
        do {
            let client = LiveAPIClient(host: session.host, accessToken: session.accessToken)
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

// MARK: - Building blocks

/// The hero: today's gross volume, the day's delta, and — when the backend
/// provides hourly data — the cumulative today-vs-yesterday curve.
private struct HeroCard: View {
    let today: Decimal
    let yesterday: Decimal
    let hourlyToday: [HourPoint]
    let hourlyYesterday: [HourPoint]
    let trend: [DayRevenue]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TODAY'S GROSS VOLUME")
                .font(.caption.weight(.semibold)).tracking(1.0).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(Fmt.money(today))
                    .font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                DeltaPill(delta: AdminDashboardStats.change(today, vs: yesterday))
            }
            Text("vs \(Fmt.money(yesterday)) yesterday")
                .font(.subheadline).foregroundStyle(.secondary)

            if hourlyToday.count > 1 || hourlyYesterday.count > 1 {
                // Show the intraday chart whenever either day has data — so before
                // today's first sale you still see yesterday's curve.
                HourlyComparisonChart(today: hourlyToday, yesterday: hourlyYesterday)
                    .frame(height: 120).padding(.top, 6)
            } else if trend.count > 2 {
                // Fallback until hourly data ships: the recent daily trend. Drop the
                // last point — it's the in-progress UTC day, so it nosedives to ~0.
                VStack(alignment: .leading, spacing: 4) {
                    Sparkline(points: trend.dropLast().map { dbl($0.revenue) }).frame(height: 54)
                    Text("DAILY TREND · COMPLETED DAYS").font(.caption2.weight(.semibold)).tracking(0.6)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 4)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

/// Sales per hour (UTC), exactly as the backend sends them — today solid,
/// yesterday dashed. Each hour's value is plotted at the end of that hour
/// (hour 0 covers 00:00–01:00 → the `1` mark), with a 0 start so a single
/// hour still draws a line up to its value.
private struct HourlyComparisonChart: View {
    let today: [HourPoint]
    let yesterday: [HourPoint]

    var body: some View {
        Chart {
            ForEach(Self.points(yesterday), id: \.x) { p in
                LineMark(x: .value("Hour", p.x), y: .value("Sales", p.v),
                         series: .value("Day", "Yesterday"))
                    .foregroundStyle(.gray)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }
            ForEach(Self.points(today), id: \.x) { p in
                LineMark(x: .value("Hour", p.x), y: .value("Sales", p.v),
                         series: .value("Day", "Today"))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .symbol(Circle())
            }
        }
        .chartForegroundStyleScale(["Today": Color.accentColor, "Yesterday": Color.gray])
        .chartXScale(domain: 0...24)
        .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 24]) { v in
            AxisGridLine()
            AxisValueLabel { if let h = v.as(Int.self) { Text(String(format: "%02d:00", h)) } }
        } }
        .chartLegend(position: .top, alignment: .leading, spacing: 8)
    }

    /// Backend values plotted at the end of each hour, prefixed with a 0 origin.
    static func points(_ src: [HourPoint]) -> [(x: Int, v: Double)] {
        var out: [(x: Int, v: Double)] = [(0, 0)]
        for p in src.sorted(by: { $0.hour < $1.hour }) {
            out.append((p.hour + 1, dbl(p.revenue)))
        }
        return out
    }
}


private struct DeltaPill: View {
    let delta: Decimal?
    var body: some View {
        if let delta {
            let up = delta >= 0
            Label("\(up ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(1))))%",
                  systemImage: up ? "arrow.up.right" : "arrow.down.right")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(up ? .green : .red)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background((up ? Color.green : .red).opacity(0.16), in: Capsule())
        }
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

private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

private struct MetricItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let icon: String?
    let tint: Color
    let delta: Decimal?
    let sub: String?

    init(_ title: String, _ value: String, _ icon: String, _ tint: Color) {
        self.title = title; self.value = value; self.icon = icon; self.tint = tint; self.delta = nil; self.sub = nil
    }
    static func comparison(_ title: String, _ value: String, _ delta: Decimal?, _ sub: String) -> MetricItem {
        MetricItem(title: title, value: value, delta: delta, sub: sub)
    }
    private init(title: String, value: String, delta: Decimal?, sub: String) {
        self.title = title; self.value = value; self.icon = nil; self.tint = .secondary; self.delta = delta; self.sub = sub
    }
}

private struct MetricGrid: View {
    let items: [MetricItem]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 14)], spacing: 14) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    if let icon = item.icon { Image(systemName: icon).foregroundStyle(item.tint).font(.title3) }
                    Text(item.value).font(.title3.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.55)
                    Text(item.title).font(.caption).foregroundStyle(.secondary)
                    if let delta = item.delta {
                        let up = delta >= 0
                        Text("\(up ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(1))))%")
                            .font(.caption.weight(.semibold)).foregroundStyle(up ? .green : .red)
                    }
                    if let sub = item.sub { Text(sub).font(.caption2).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
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
        }
        .chartForegroundStyleScale(["This period": Color.accentColor, "Previous": Color.gray])
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
    }
}

private struct RevenueBarChart: View {
    let items: [(String, Decimal)]
    /// Cap on x-axis labels — keeps month names from colliding on a phone.
    var desiredLabels = 8
    var body: some View {
        Chart(Array(items.enumerated()), id: \.offset) { i, item in
            BarMark(x: .value("Index", i), y: .value("Revenue", dbl(item.1)))
                .foregroundStyle(Color.accentColor)
        }
        .chartXAxis {
            AxisMarks(values: tickIndices(count: items.count, desired: desiredLabels)) { value in
                if let i = value.as(Int.self), items.indices.contains(i) {
                    AxisValueLabel(orientation: .verticalReversed) { Text(items[i].0) }
                }
            }
        }
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
        VStack(spacing: 8) {
            ForEach(items.prefix(5)) { item in
                VStack(alignment: .leading, spacing: 3) {
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
                }
            }
        }
    }
}

private func dbl(_ d: Decimal) -> Double { (d as NSDecimalNumber).doubleValue }

/// Dashboard date-range options (sent as `?date_range=`). `year_to_date` is the
/// new value the backend added alongside the existing ones.
enum DashRange: String, CaseIterable, Identifiable {
    case today
    case last7 = "last_7_days"
    case monthToDate = "month_to_date"
    case yearToDate = "year_to_date"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .today: "Today"
        case .last7: "Last 7 days"
        case .monthToDate: "Month to date"
        case .yearToDate: "Year to date"
        }
    }
}

enum Fmt {
    /// One consistent rule: abbreviate at/above $1,000 ($2.3K, $129K, $2.0M);
    /// show exact dollars and cents below ($12.90).
    static func money(_ d: Decimal) -> String {
        let v = dbl(d)
        if abs(v) >= 1000 {
            return "$" + v.formatted(.number.notation(.compactName).precision(.fractionLength(1)))
        }
        return "$" + d.formatted(.number.precision(.fractionLength(2)).grouping(.automatic))
    }
    static func countCompact(_ n: Int) -> String {
        n >= 1000 ? Double(n).formatted(.number.notation(.compactName).precision(.fractionLength(1))) : n.formatted()
    }
}
