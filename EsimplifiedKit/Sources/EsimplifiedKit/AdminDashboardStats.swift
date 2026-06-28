import Foundation

/// A `{ label, count }` row (top packages / top countries).
public struct LabeledCount: Identifiable, Equatable, Sendable {
    public var id: String { label }
    public let label: String
    public let count: Int
    public init(label: String, count: Int) { self.label = label; self.count = count }
}

/// A `{ month, amount }` point (revenue per month).
public struct MonthRevenue: Identifiable, Equatable, Sendable {
    public var id: String { month }
    public let month: String
    public let amount: Decimal
    public init(month: String, amount: Decimal) { self.month = month; self.amount = amount }
}

/// One slot in the trailing 12-month chart — current month vs the same slot one
/// year earlier in the prior 12-month block (e.g. Jul '25 vs Jul '24).
public struct MonthRevenueComparisonPoint: Identifiable, Equatable, Sendable {
    public var id: String { currentMonth }
    public let currentMonth: String
    public let previousMonth: String
    public let current: Decimal
    public let previous: Decimal
    public init(currentMonth: String, previousMonth: String, current: Decimal, previous: Decimal) {
        self.currentMonth = currentMonth; self.previousMonth = previousMonth
        self.current = current; self.previous = previous
    }
}

/// Per-tenant revenue: all-time plus today's and yesterday's calendar-day totals (UTC).
public struct TenantRevenueSlice: Identifiable, Equatable, Sendable {
    public var id: String { tenant }
    public let tenant: String
    public let overall: Decimal
    public let today: Decimal
    public let yesterday: Decimal
    public init(tenant: String, overall: Decimal, today: Decimal = 0, yesterday: Decimal = 0) {
        self.tenant = tenant; self.overall = overall; self.today = today; self.yesterday = yesterday
    }
}

/// A `{ hour, revenue }` point for the intraday today/yesterday series.
public struct HourPoint: Identifiable, Equatable, Sendable {
    public var id: Int { hour }
    public let hour: Int
    public let revenue: Decimal
    public init(hour: Int, revenue: Decimal) { self.hour = hour; self.revenue = revenue }
}

/// A `{ date, revenue }` point in the daily revenue series.
public struct DayRevenue: Decodable, Equatable, Sendable {
    public let date: String
    public let revenue: Decimal

    public init(date: String, revenue: Decimal) {
        self.date = date
        self.revenue = revenue
    }

    private enum CodingKeys: String, CodingKey { case date, revenue }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        revenue = try c.decode(FlexibleDecimal.self, forKey: .revenue).value
    }
}

/// A period bucket (`current` = this period, `comparison` = the previous one).
public struct StatsPeriod: Decodable, Equatable, Sendable {
    public let revenue: Decimal
    public let averageOrderValue: Decimal
    public let customers: Int
    public let orders: Int
    public let revenuePerDate: [DayRevenue]
    public let topPackages: [LabeledCount]
    public let topCountries: [LabeledCount]

    static let empty = StatsPeriod(revenue: 0, averageOrderValue: 0, customers: 0, orders: 0,
                                   revenuePerDate: [], topPackages: [], topCountries: [])

    init(revenue: Decimal, averageOrderValue: Decimal, customers: Int, orders: Int,
         revenuePerDate: [DayRevenue], topPackages: [LabeledCount], topCountries: [LabeledCount]) {
        self.revenue = revenue; self.averageOrderValue = averageOrderValue
        self.customers = customers; self.orders = orders
        self.revenuePerDate = revenuePerDate; self.topPackages = topPackages; self.topCountries = topCountries
    }

    private enum K: String, CodingKey {
        case revenue, customers
        case averageOrderValue = "average_order_value"
        case successOrders = "success_orders"
        case revenuePerDate = "revenue_per_date"
        case topPackages = "top_packages"
        case topCountries = "top_countries"
    }
    private struct PkgDTO: Decodable { let package_name: String?; let count: Int? }
    private struct CountryDTO: Decodable { let country: String?; let count: Int? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        revenue = (try c.decodeIfPresent(FlexibleDecimal.self, forKey: .revenue))?.value ?? 0
        averageOrderValue = (try c.decodeIfPresent(FlexibleDecimal.self, forKey: .averageOrderValue))?.value ?? 0
        customers = try c.decodeIfPresent(Int.self, forKey: .customers) ?? 0
        orders = try c.decodeIfPresent(Int.self, forKey: .successOrders) ?? 0
        revenuePerDate = try c.decodeIfPresent([DayRevenue].self, forKey: .revenuePerDate) ?? []
        topPackages = (try c.decodeIfPresent([PkgDTO].self, forKey: .topPackages) ?? [])
            .map { LabeledCount(label: $0.package_name ?? "—", count: $0.count ?? 0) }
        topCountries = (try c.decodeIfPresent([CountryDTO].self, forKey: .topCountries) ?? [])
            .map { LabeledCount(label: $0.country ?? "—", count: $0.count ?? 0) }
    }
}

/// The admin dashboard's view of the `/api/statistics/` response (DashboardData).
public struct AdminDashboardStats: Decodable, Sendable {
    public let tenants: Int
    public let successOrders: Int
    public let customers: Int
    public let revenue: Decimal
    /// All-time highest-revenue day across the caller's tenants; not scoped by
    /// `date_range`. Null when there have been no paid (SUCCESS) orders.
    public let bestDay: DayRevenue?
    public let revenueToday: Decimal
    public let revenueYesterday: Decimal
    public let revenueCurrentMonth: Decimal
    public let revenueLastMonth: Decimal
    public let averageOrderValue: Decimal
    public let revenuePerDate: [DayRevenue]
    public let revenuePerMonth: [MonthRevenue]
    public let revenuePerTenant: [TenantRevenueSlice]
    /// Per-hour revenue increments (UTC, hour 0→now) for today and yesterday.
    /// Empty until the backend ships these fields.
    public let revenuePerHourToday: [HourPoint]
    public let revenuePerHourYesterday: [HourPoint]
    public let current: StatsPeriod
    public let comparison: StatsPeriod

    private enum K: String, CodingKey {
        case tenants, customers, revenue, current, comparison
        case bestDay = "best_day"
        case successOrders = "success_orders"
        case revenueToday = "revenue_today"
        case revenueYesterday = "revenue_yesterday"
        case revenueCurrentMonth = "revenue_current_month"
        case revenueLastMonth = "revenue_last_month"
        case averageOrderValue = "average_order_value"
        case revenuePerDate = "revenue_per_date"
        case revenuePerMonth = "revenue_per_month"
        case revenuePerTenant = "revenue_per_tenant"
        case revenuePerHourToday = "revenue_per_hour_today"
        case revenuePerHourYesterday = "revenue_per_hour_yesterday"
    }
    private struct HourDTO: Decodable { let hour: Int?; let revenue: FlexibleDecimal? }

    /// `{ overall, today, yesterday }` per tenant — flat legacy numbers are ignored.
    private struct TenantRevenueEntry: Decodable {
        let overall: Decimal
        let today: Decimal
        let yesterday: Decimal

        private enum K: String, CodingKey { case overall, today, yesterday }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            overall = (try c.decode(FlexibleDecimal.self, forKey: .overall)).value
            today = (try c.decodeIfPresent(FlexibleDecimal.self, forKey: .today))?.value ?? 0
            yesterday = (try c.decodeIfPresent(FlexibleDecimal.self, forKey: .yesterday))?.value ?? 0
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        func money(_ key: K) throws -> Decimal { (try c.decodeIfPresent(FlexibleDecimal.self, forKey: key))?.value ?? 0 }
        tenants = try c.decodeIfPresent(Int.self, forKey: .tenants) ?? 0
        successOrders = try c.decodeIfPresent(Int.self, forKey: .successOrders) ?? 0
        customers = try c.decodeIfPresent(Int.self, forKey: .customers) ?? 0
        revenue = try money(.revenue)
        bestDay = try c.decodeIfPresent(DayRevenue.self, forKey: .bestDay)
        revenueToday = try money(.revenueToday)
        revenueYesterday = try money(.revenueYesterday)
        revenueCurrentMonth = try money(.revenueCurrentMonth)
        revenueLastMonth = try money(.revenueLastMonth)
        averageOrderValue = try money(.averageOrderValue)
        revenuePerDate = try c.decodeIfPresent([DayRevenue].self, forKey: .revenuePerDate) ?? []

        let months = try c.decodeIfPresent([String: FlexibleDecimal].self, forKey: .revenuePerMonth) ?? [:]
        revenuePerMonth = months.map { MonthRevenue(month: $0.key, amount: $0.value.value) }
            .sorted { $0.month < $1.month }

        // Old backends still send flat numbers — that shape can't decode here, so
        // treat the whole field as absent until the nested object ships.
        let perTenant = (try? c.decode([String: TenantRevenueEntry].self, forKey: .revenuePerTenant)) ?? [:]
        revenuePerTenant = perTenant.map {
            TenantRevenueSlice(tenant: $0.key, overall: $0.value.overall,
                               today: $0.value.today, yesterday: $0.value.yesterday)
        }.sorted { $0.overall > $1.overall }

        func hours(_ key: K) throws -> [HourPoint] {
            (try c.decodeIfPresent([HourDTO].self, forKey: key) ?? []).compactMap {
                guard let h = $0.hour else { return nil }
                return HourPoint(hour: h, revenue: $0.revenue?.value ?? 0)
            }.sorted { $0.hour < $1.hour }
        }
        revenuePerHourToday = try hours(.revenuePerHourToday)
        revenuePerHourYesterday = try hours(.revenuePerHourYesterday)

        current = try c.decodeIfPresent(StatsPeriod.self, forKey: .current) ?? .empty
        comparison = try c.decodeIfPresent(StatsPeriod.self, forKey: .comparison) ?? .empty
    }

    /// Tenants ranked by today's revenue (UTC calendar day), highest first.
    public var tenantsByTodayRevenue: [TenantRevenueSlice] {
        revenuePerTenant.sorted { $0.today > $1.today }
    }

    /// Percentage change of today vs yesterday; nil when yesterday is zero.
    public var deltaPercent: Decimal? {
        guard revenueYesterday != 0 else { return nil }
        return (revenueToday - revenueYesterday) / revenueYesterday * 100
    }

    /// Percentage change of a current value vs the comparison period; nil when the base is zero.
    public static func change(_ current: Decimal, vs previous: Decimal) -> Decimal? {
        guard previous != 0 else { return nil }
        return (current - previous) / previous * 100
    }

    /// Yesterday's cumulative revenue through the given UTC hour (inclusive), summed
    /// from the hourly series — i.e. "yesterday to date" for a same-time-of-day
    /// comparison. nil when there's no yesterday hourly data (so callers fall back to
    /// the full-day figure rather than comparing today-so-far against a whole day).
    public func revenueYesterdayThroughHour(_ hour: Int) -> Decimal? {
        guard !revenuePerHourYesterday.isEmpty else { return nil }
        return revenuePerHourYesterday
            .filter { $0.hour <= hour }
            .reduce(Decimal(0)) { $0 + $1.revenue }
    }

    /// Percentage change of today-so-far vs yesterday through the same UTC hour
    /// ("to date"); nil when there's no hourly data or yesterday-to-date is zero.
    public func deltaPercentToDate(currentHour: Int) -> Decimal? {
        guard let base = revenueYesterdayThroughHour(currentHour) else { return nil }
        return Self.change(revenueToday, vs: base)
    }

    /// `YYYY-MM` keys for `count` consecutive months ending at `cap`, oldest first.
    private static func monthKeys(ending cap: String, count: Int) -> [String] {
        guard count > 0, cap.count >= 7,
              var y = Int(cap.prefix(4)),
              var m = Int(cap.dropFirst(5).prefix(2)) else { return [] }
        var keys: [String] = []
        for _ in 0..<count {
            keys.append(String(format: "%04d-%02d", y, m))
            m -= 1
            if m == 0 { m = 12; y -= 1 }
        }
        return keys.reversed()
    }

    /// Last 12 months ending at `through` (default: current UTC month), each paired
    /// with the matching month from the prior 12-month block. Missing API entries
    /// decode as zero — one bar per side, no aggregation.
    public func revenuePerMonthComparison(through cap: String = utcYearMonthNow()) -> [MonthRevenueComparisonPoint] {
        let currentKeys = Self.monthKeys(ending: cap, count: 12)
        let previousKeys = Self.monthKeys(ending: cap, count: 24).prefix(12)
        guard currentKeys.count == 12, previousKeys.count == 12 else { return [] }

        let byMonth = Dictionary(uniqueKeysWithValues: revenuePerMonth.map { ($0.month, $0.amount) })
        return zip(currentKeys, previousKeys).map { cur, prev in
            MonthRevenueComparisonPoint(
                currentMonth: cur, previousMonth: prev,
                current: byMonth[cur] ?? 0, previous: byMonth[prev] ?? 0)
        }
    }

    /// Last-12 slice of `revenuePerMonthComparison` (current side only).
    public func revenuePerMonthChart(through cap: String = utcYearMonthNow()) -> [MonthRevenue] {
        revenuePerMonthComparison(through: cap).map { MonthRevenue(month: $0.currentMonth, amount: $0.current) }
    }

    /// Sum of the current UTC calendar year's monthly revenue.
    public var revenueThisYear: Decimal {
        let year = utcYearMonthNow().prefix(4)
        return revenuePerMonth.filter { $0.month.hasPrefix(String(year)) }.reduce(0) { $0 + $1.amount }
    }

    /// Sum of the previous UTC calendar year's monthly revenue.
    public var revenueLastYear: Decimal {
        guard let y = Int(utcYearMonthNow().prefix(4)) else { return 0 }
        let prev = String(y - 1)
        return revenuePerMonth.filter { $0.month.hasPrefix(prev) }.reduce(0) { $0 + $1.amount }
    }
}
