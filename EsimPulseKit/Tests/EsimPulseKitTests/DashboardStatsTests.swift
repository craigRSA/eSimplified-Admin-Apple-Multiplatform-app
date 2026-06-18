import XCTest
@testable import EsimPulseKit

final class DashboardStatsTests: XCTestCase {
    private func fixtureData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "statistics_response",
                                                  withExtension: "json",
                                                  subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func test_decode_parses_string_decimals_from_real_response() throws {
        let stats = try DashboardStats.decode(from: try fixtureData())

        XCTAssertEqual(stats.revenueToday, Decimal(string: "1523.45"))
        XCTAssertEqual(stats.revenueYesterday, Decimal(string: "1402.10"))
        XCTAssertEqual(stats.successOrders, 87)
        XCTAssertEqual(stats.revenuePerDate.count, 3)
        XCTAssertEqual(stats.revenuePerDate.last,
                       DayRevenue(date: "2026-06-13", revenue: Decimal(string: "1523.45")!))
    }

    func test_decode_accepts_numeric_decimals() throws {
        let json = """
        { "revenue_today": 10.5, "revenue_yesterday": 9,
          "current": { "success_orders": 3, "revenue_per_date": [] } }
        """
        let stats = try DashboardStats.decode(from: Data(json.utf8))

        XCTAssertEqual(stats.revenueToday, Decimal(string: "10.5"))
        XCTAssertEqual(stats.revenueYesterday, Decimal(string: "9"))
        XCTAssertEqual(stats.successOrders, 3)
    }
}
