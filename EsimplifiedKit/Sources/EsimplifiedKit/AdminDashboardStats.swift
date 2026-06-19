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

/// A `{ tenant, amount }` slice (revenue per tenant).
public struct TenantRevenueSlice: Identifiable, Equatable, Sendable {
    public var id: String { tenant }
    public let tenant: String
    public let amount: Decimal
    public init(tenant: String, amount: Decimal) { self.tenant = tenant; self.amount = amount }
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
    public let revenueToday: Decimal
    public let revenueYesterday: Decimal
    public let revenueCurrentMonth: Decimal
    public let revenueLastMonth: Decimal
    public let averageOrderValue: Decimal
    public let revenuePerDate: [DayRevenue]
    public let revenuePerMonth: [MonthRevenue]
    public let revenuePerTenant: [TenantRevenueSlice]
    public let current: StatsPeriod
    public let comparison: StatsPeriod

    private enum K: String, CodingKey {
        case tenants, customers, revenue, current, comparison
        case successOrders = "success_orders"
        case revenueToday = "revenue_today"
        case revenueYesterday = "revenue_yesterday"
        case revenueCurrentMonth = "revenue_current_month"
        case revenueLastMonth = "revenue_last_month"
        case averageOrderValue = "average_order_value"
        case revenuePerDate = "revenue_per_date"
        case revenuePerMonth = "revenue_per_month"
        case revenuePerTenant = "revenue_per_tenant"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        func money(_ key: K) throws -> Decimal { (try c.decodeIfPresent(FlexibleDecimal.self, forKey: key))?.value ?? 0 }
        tenants = try c.decodeIfPresent(Int.self, forKey: .tenants) ?? 0
        successOrders = try c.decodeIfPresent(Int.self, forKey: .successOrders) ?? 0
        customers = try c.decodeIfPresent(Int.self, forKey: .customers) ?? 0
        revenue = try money(.revenue)
        revenueToday = try money(.revenueToday)
        revenueYesterday = try money(.revenueYesterday)
        revenueCurrentMonth = try money(.revenueCurrentMonth)
        revenueLastMonth = try money(.revenueLastMonth)
        averageOrderValue = try money(.averageOrderValue)
        revenuePerDate = try c.decodeIfPresent([DayRevenue].self, forKey: .revenuePerDate) ?? []

        let months = try c.decodeIfPresent([String: FlexibleDecimal].self, forKey: .revenuePerMonth) ?? [:]
        revenuePerMonth = months.map { MonthRevenue(month: $0.key, amount: $0.value.value) }
            .sorted { $0.month < $1.month }

        let perTenant = try c.decodeIfPresent([String: FlexibleDecimal].self, forKey: .revenuePerTenant) ?? [:]
        revenuePerTenant = perTenant.map { TenantRevenueSlice(tenant: $0.key, amount: $0.value.value) }
            .sorted { $0.amount > $1.amount }

        current = try c.decodeIfPresent(StatsPeriod.self, forKey: .current) ?? .empty
        comparison = try c.decodeIfPresent(StatsPeriod.self, forKey: .comparison) ?? .empty
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
}
