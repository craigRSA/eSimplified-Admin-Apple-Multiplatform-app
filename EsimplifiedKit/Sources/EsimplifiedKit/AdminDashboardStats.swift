import Foundation

/// The admin dashboard's view of the `/api/statistics/` response (DashboardData).
/// Reads the top-level fields the web admin dashboard displays; money fields use
/// `FlexibleDecimal` (DRF may send strings or numbers) and every field is tolerant
/// of being absent.
public struct AdminDashboardStats: Decodable, Equatable, Sendable {
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

    private enum K: String, CodingKey {
        case tenants, customers, revenue
        case successOrders = "success_orders"
        case revenueToday = "revenue_today"
        case revenueYesterday = "revenue_yesterday"
        case revenueCurrentMonth = "revenue_current_month"
        case revenueLastMonth = "revenue_last_month"
        case averageOrderValue = "average_order_value"
        case revenuePerDate = "revenue_per_date"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        func money(_ key: K) throws -> Decimal {
            (try c.decodeIfPresent(FlexibleDecimal.self, forKey: key))?.value ?? 0
        }
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
    }

    /// Percentage change of today vs yesterday; nil when yesterday is zero.
    public var deltaPercent: Decimal? {
        guard revenueYesterday != 0 else { return nil }
        return (revenueToday - revenueYesterday) / revenueYesterday * 100
    }
}
