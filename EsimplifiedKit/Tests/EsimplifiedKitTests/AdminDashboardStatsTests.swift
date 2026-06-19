import XCTest
@testable import EsimplifiedKit

final class AdminDashboardStatsTests: XCTestCase {
    func test_decode_hourly_series_today_and_yesterday() throws {
        let json = """
        {
          "revenue_today": "305.50",
          "revenue_per_hour_today": [
            { "hour": 0, "revenue": "120.00" },
            { "hour": 1, "revenue": 0 },
            { "hour": 2, "revenue": 185.50 }
          ],
          "revenue_per_hour_yesterday": [
            { "hour": 2, "revenue": "90.00" },
            { "hour": 0, "revenue": "95.00" }
          ]
        }
        """
        let stats = try JSONDecoder().decode(AdminDashboardStats.self, from: Data(json.utf8))
        XCTAssertEqual(stats.revenuePerHourToday.map(\.hour), [0, 1, 2]) // sorted
        XCTAssertEqual(stats.revenuePerHourToday[2].revenue, Decimal(string: "185.50"))
        XCTAssertEqual(stats.revenuePerHourYesterday.map(\.hour), [0, 2]) // sorted
        XCTAssertEqual(stats.revenuePerHourYesterday.first?.revenue, Decimal(string: "95.00"))
    }

    func test_decode_absent_hourly_is_empty() throws {
        let stats = try JSONDecoder().decode(AdminDashboardStats.self, from: Data("{}".utf8))
        XCTAssertTrue(stats.revenuePerHourToday.isEmpty)
        XCTAssertTrue(stats.revenuePerHourYesterday.isEmpty)
    }


    func test_decode_real_shaped_response_mixed_string_and_number_decimals() throws {
        // Mirrors the backend DashboardData shape: top-level money fields, some as
        // DRF strings, plus revenue_per_date.
        let json = """
        {
          "tenants": 5,
          "success_orders": 1234,
          "customers": 980,
          "revenue": "100000.00",
          "revenue_today": "1523.45",
          "revenue_yesterday": 1402.10,
          "revenue_current_month": "25000.00",
          "revenue_last_month": "31000.00",
          "average_order_value": "12.34",
          "revenue_per_date": [
            { "date": "2026-06-17", "revenue": "1100.00" },
            { "date": "2026-06-18", "revenue": 1250.50 },
            { "date": "2026-06-19", "revenue": "1523.45" }
          ],
          "current": { "success_orders": 87 }
        }
        """
        let stats = try JSONDecoder().decode(AdminDashboardStats.self, from: Data(json.utf8))
        XCTAssertEqual(stats.tenants, 5)
        XCTAssertEqual(stats.successOrders, 1234)
        XCTAssertEqual(stats.customers, 980)
        XCTAssertEqual(stats.revenue, Decimal(string: "100000.00"))
        XCTAssertEqual(stats.revenueToday, Decimal(string: "1523.45"))
        XCTAssertEqual(stats.revenueYesterday, Decimal(string: "1402.10"))
        XCTAssertEqual(stats.revenueCurrentMonth, Decimal(string: "25000.00"))
        XCTAssertEqual(stats.revenueLastMonth, Decimal(string: "31000.00"))
        XCTAssertEqual(stats.averageOrderValue, Decimal(string: "12.34"))
        XCTAssertEqual(stats.revenuePerDate.count, 3)
        XCTAssertEqual(stats.revenuePerDate.last, DayRevenue(date: "2026-06-19", revenue: Decimal(string: "1523.45")!))
        XCTAssertEqual(stats.deltaPercent, (Decimal(string: "1523.45")! - Decimal(string: "1402.10")!) / Decimal(string: "1402.10")! * 100)
    }

    func test_best_day_and_yearly_rollups_derive_from_series() throws {
        let json = """
        {
          "revenue_per_month": {"2025-11":"1000","2025-12":"2000","2026-01":"3000","2026-06":"5000"},
          "current": {"revenue_per_date":[
            {"date":"2026-06-01","revenue":"100"},
            {"date":"2026-06-02","revenue":"950.50"},
            {"date":"2026-06-03","revenue":"300"}
          ]}
        }
        """
        let s = try JSONDecoder().decode(AdminDashboardStats.self, from: Data(json.utf8))
        XCTAssertEqual(s.bestDay, DayRevenue(date: "2026-06-02", revenue: Decimal(string: "950.50")!))
        XCTAssertEqual(s.revenueThisYear, Decimal(string: "8000"))   // 3000 + 5000 (2026)
        XCTAssertEqual(s.revenueLastYear, Decimal(string: "3000"))   // 1000 + 2000 (2025)
    }

    func test_decode_tolerates_missing_fields() throws {
        let stats = try JSONDecoder().decode(AdminDashboardStats.self, from: Data("{}".utf8))
        XCTAssertEqual(stats.tenants, 0)
        XCTAssertEqual(stats.revenue, 0)
        XCTAssertEqual(stats.revenuePerDate, [])
        XCTAssertNil(stats.deltaPercent)
    }
}
