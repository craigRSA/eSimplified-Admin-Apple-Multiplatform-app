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

    func test_revenueYesterdayThroughHour_cumulative_and_toDateDelta() throws {
        // Yesterday's hourly buckets, with hour 2 deliberately absent (a gap).
        let json = """
        {
          "revenue_today": "50.00",
          "revenue_per_hour_yesterday": [
            { "hour": 0, "revenue": "10.00" },
            { "hour": 1, "revenue": "20.00" },
            { "hour": 3, "revenue": "30.00" }
          ]
        }
        """
        let s = try JSONDecoder().decode(AdminDashboardStats.self, from: Data(json.utf8))
        // Cumulative sum of buckets with hour <= the given UTC hour (inclusive).
        XCTAssertEqual(s.revenueYesterdayThroughHour(0), Decimal(string: "10.00"))
        XCTAssertEqual(s.revenueYesterdayThroughHour(1), Decimal(string: "30.00"))  // 10+20
        XCTAssertEqual(s.revenueYesterdayThroughHour(2), Decimal(string: "30.00"))  // hour 2 absent → unchanged
        XCTAssertEqual(s.revenueYesterdayThroughHour(3), Decimal(string: "60.00"))  // +30
        XCTAssertEqual(s.revenueYesterdayThroughHour(12), Decimal(string: "60.00")) // beyond last → full cumulative
        // "to date" delta: today 50 vs yesterday-through-hour-1 (30) → +66.67%
        XCTAssertEqual(s.deltaPercentToDate(currentHour: 1), (Decimal(50) - 30) / 30 * 100)
    }

    func test_toDate_nilWhenNoYesterdayHourly() throws {
        // No hourly series → the caller must fall back to the full-day comparison.
        let s = try JSONDecoder().decode(AdminDashboardStats.self, from: Data(#"{ "revenue_today": "50.00" }"#.utf8))
        XCTAssertNil(s.revenueYesterdayThroughHour(10))
        XCTAssertNil(s.deltaPercentToDate(currentHour: 10))
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

    func test_best_day_and_yearly_rollups() throws {
        let json = """
        {
          "revenue_per_month": {"2025-11":"1000","2025-12":"2000","2026-01":"3000","2026-06":"5000"},
          "best_day": {"date":"2026-06-02","revenue":"950.50"},
          "revenue_per_date":[
            {"date":"2026-06-01","revenue":"100"},
            {"date":"2026-06-02","revenue":"950.50"},
            {"date":"2026-06-03","revenue":"300"}
          ]
        }
        """
        let s = try JSONDecoder().decode(AdminDashboardStats.self, from: Data(json.utf8))
        XCTAssertEqual(s.bestDay, DayRevenue(date: "2026-06-02", revenue: Decimal(string: "950.50")!))
        XCTAssertEqual(s.revenueThisYear, Decimal(string: "8000"))   // 3000 + 5000 (2026)
        XCTAssertEqual(s.revenueLastYear, Decimal(string: "3000"))   // 1000 + 2000 (2025)
    }

    func test_best_day_absent_before_backend_ships() throws {
        let s = try JSONDecoder().decode(AdminDashboardStats.self, from: Data("{}".utf8))
        XCTAssertNil(s.bestDay)
    }

    func test_decode_top_level_best_day() throws {
        let json = """
        {
          "best_day": {"date":"2026-06-02","revenue":"950.50"},
          "revenue_per_date": [{"date":"2026-06-01","revenue":"100"}]
        }
        """
        let s = try JSONDecoder().decode(AdminDashboardStats.self, from: Data(json.utf8))
        XCTAssertEqual(s.bestDay, DayRevenue(date: "2026-06-02", revenue: Decimal(string: "950.50")!))
    }

    func test_top_level_best_day_null_when_no_sales() throws {
        let json = """
        {
          "best_day": null,
          "revenue_per_date": []
        }
        """
        let s = try JSONDecoder().decode(AdminDashboardStats.self, from: Data(json.utf8))
        XCTAssertNil(s.bestDay)
    }

    func test_decode_tolerates_missing_fields() throws {
        let stats = try JSONDecoder().decode(AdminDashboardStats.self, from: Data("{}".utf8))
        XCTAssertEqual(stats.tenants, 0)
        XCTAssertEqual(stats.revenue, 0)
        XCTAssertEqual(stats.revenuePerDate, [])
        XCTAssertNil(stats.deltaPercent)
    }

    func test_decode_revenue_per_tenant_object_shape() throws {
        let json = """
        {
          "revenue_per_tenant": {
            "Acme":   { "overall": "12345.00", "today": "120.00", "yesterday": "95.00" },
            "Globex": { "overall": 6789, "today": 0, "yesterday": 40 }
          }
        }
        """
        let s = try JSONDecoder().decode(AdminDashboardStats.self, from: Data(json.utf8))
        XCTAssertEqual(s.revenuePerTenant.count, 2)
        let acme = s.revenuePerTenant.first { $0.tenant == "Acme" }
        XCTAssertEqual(acme?.overall, Decimal(string: "12345.00"))
        XCTAssertEqual(acme?.today, Decimal(string: "120.00"))
        XCTAssertEqual(acme?.yesterday, Decimal(string: "95.00"))
        let globex = s.revenuePerTenant.first { $0.tenant == "Globex" }
        XCTAssertEqual(globex?.overall, Decimal(string: "6789"))
        XCTAssertEqual(globex?.today, 0)
        XCTAssertEqual(globex?.yesterday, Decimal(string: "40"))
        // All-time chart order: Acme first.
        XCTAssertEqual(s.revenuePerTenant.first?.tenant, "Acme")
        // Today leaderboard: Acme only (Globex today is zero).
        XCTAssertEqual(s.tenantsByTodayRevenue.filter { $0.today > 0 }.map(\.tenant), ["Acme"])
    }

    func test_revenuePerMonthChart_drops_future_and_caps_at_twelve() throws {
        let json = """
        {
          "revenue_per_month": {
            "2024-01": "1",
            "2025-07": "70", "2025-08": "80", "2025-09": "90",
            "2025-10": "2", "2025-11": "3", "2025-12": "4",
            "2026-01": "5", "2026-02": "6", "2026-03": "7", "2026-04": "8",
            "2026-05": "9", "2026-06": "10", "2026-07": "11", "2026-08": "12", "2026-09": "13"
          }
        }
        """
        let s = try JSONDecoder().decode(AdminDashboardStats.self, from: Data(json.utf8))
        let chart = s.revenuePerMonthChart(through: "2026-06")
        XCTAssertEqual(chart.count, 12)
        XCTAssertEqual(chart.first?.month, "2025-07")
        XCTAssertEqual(chart.last?.month, "2026-06")
        XCTAssertEqual(chart.last?.amount, Decimal(string: "10"))
        XCTAssertFalse(chart.contains { $0.month == "2026-09" })
    }

    func test_revenuePerMonthComparison_pairs_prior_twelve() throws {
        let json = """
        {
          "revenue_per_month": {
            "2025-07": "100", "2026-07": "200",
            "2025-08": "110", "2026-08": "210"
          }
        }
        """
        let s = try JSONDecoder().decode(AdminDashboardStats.self, from: Data(json.utf8))
        let cmp = s.revenuePerMonthComparison(through: "2026-08")
        let july = cmp.first { $0.currentMonth == "2026-07" }
        XCTAssertEqual(july?.previousMonth, "2025-07")
        XCTAssertEqual(july?.current, Decimal(string: "200"))
        XCTAssertEqual(july?.previous, Decimal(string: "100"))
        let aug = cmp.first { $0.currentMonth == "2026-08" }
        XCTAssertEqual(aug?.previousMonth, "2025-08")
        XCTAssertEqual(aug?.previous, Decimal(string: "110"))
    }

    func test_decode_revenue_per_tenant_legacy_flat_number_is_ignored() throws {
        let json = #"{"revenue_per_tenant":{"LegacyCo":"5000.00"}}"#
        let s = try JSONDecoder().decode(AdminDashboardStats.self, from: Data(json.utf8))
        XCTAssertTrue(s.revenuePerTenant.isEmpty)
    }
}
