import XCTest
@testable import EsimplifiedKit

final class HourlyRevenueTests: XCTestCase {
    func test_cumulativeHourly_accumulates_with_zero_origin() {
        let pts = cumulativeHourly([HourPoint(hour: 0, revenue: 10), HourPoint(hour: 1, revenue: 5)])
        XCTAssertEqual(pts, [CumulativeHourPoint(hour: 0, total: 0),
                             CumulativeHourPoint(hour: 1, total: 10),    // hour 0 ends at x1
                             CumulativeHourPoint(hour: 2, total: 15)])   // running total
    }

    func test_cumulativeHourly_capsCurrentHourAtNow() {
        // Hour 8 in progress at 08:30 → plotted at x 8.5, not its end (9).
        let pts = cumulativeHourly([HourPoint(hour: 8, revenue: 20)], cappedAt: 8.5)
        XCTAssertEqual(pts.last, CumulativeHourPoint(hour: 8.5, total: 20))
    }

    func test_cumulativeHourly_completedHoursUnaffectedByCap() {
        // Hour 6 ends at x7, which is before "now" (8.5), so the cap leaves it alone.
        let pts = cumulativeHourly([HourPoint(hour: 6, revenue: 1)], cappedAt: 8.5)
        XCTAssertEqual(pts.last, CumulativeHourPoint(hour: 7, total: 1))
    }

    func test_cumulativeHourly_emptyIsJustTheOrigin() {
        XCTAssertEqual(cumulativeHourly([]), [CumulativeHourPoint(hour: 0, total: 0)])
    }
}
