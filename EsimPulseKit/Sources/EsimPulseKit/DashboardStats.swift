import Foundation

/// Decodes a Decimal that may arrive as a JSON string (DRF default) or a JSON number.
struct FlexibleDecimal: Decodable {
    let value: Decimal
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self), let dec = Decimal(string: string) {
            value = dec
        } else {
            value = try container.decode(Decimal.self)
        }
    }
}

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

public struct DashboardStats: Decodable, Equatable, Sendable {
    public let revenueToday: Decimal
    public let revenueYesterday: Decimal
    public let revenuePerDate: [DayRevenue]
    public let successOrders: Int

    private enum CodingKeys: String, CodingKey {
        case revenueToday = "revenue_today"
        case revenueYesterday = "revenue_yesterday"
        case current
    }

    private enum CurrentKeys: String, CodingKey {
        case successOrders = "success_orders"
        case revenuePerDate = "revenue_per_date"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        revenueToday = try c.decode(FlexibleDecimal.self, forKey: .revenueToday).value
        revenueYesterday = try c.decode(FlexibleDecimal.self, forKey: .revenueYesterday).value

        let current = try c.nestedContainer(keyedBy: CurrentKeys.self, forKey: .current)
        successOrders = try current.decode(Int.self, forKey: .successOrders)
        revenuePerDate = try current.decodeIfPresent([DayRevenue].self, forKey: .revenuePerDate) ?? []
    }

    public static func decode(from data: Data) throws -> DashboardStats {
        try JSONDecoder().decode(DashboardStats.self, from: data)
    }
}
