import XCTest
@testable import EsimplifiedKit

@MainActor
final class DashboardViewModelTests: XCTestCase {
    private func stats(today: String, yesterday: String) -> DashboardStats {
        let json = """
        {"revenue_today":"\(today)","revenue_yesterday":"\(yesterday)",
         "current":{"success_orders":1,"revenue_per_date":[]}}
        """
        return try! DashboardStats.decode(from: Data(json.utf8))
    }

    func test_refresh_success_sets_loaded_state() async {
        let client = StubClient(result: .success(stats(today: "100", yesterday: "80")))
        let vm = DashboardViewModel(client: client)

        await vm.refresh()

        guard case let .loaded(s, stale) = vm.state else {
            XCTFail("expected .loaded, got \(vm.state)")
            return
        }
        XCTAssertEqual(s.revenueToday, Decimal(string: "100"))
        XCTAssertFalse(stale)
    }

    func test_refresh_authExpired_sets_error_state() async {
        let client = StubClient(result: .failure(.authExpired))
        let vm = DashboardViewModel(client: client)

        await vm.refresh()

        XCTAssertEqual(vm.state, .error(.authExpired))
    }

    func test_refresh_unreachable_after_loaded_keeps_last_value_as_stale() async {
        let client = StubClient(result: .success(stats(today: "100", yesterday: "80")))
        let vm = DashboardViewModel(client: client)
        await vm.refresh()

        client.result = .failure(.unreachable)
        await vm.refresh()

        guard case let .loaded(s, stale) = vm.state else {
            XCTFail("expected .loaded, got \(vm.state)")
            return
        }
        XCTAssertEqual(s.revenueToday, Decimal(string: "100"))
        XCTAssertTrue(stale)
    }

    func test_deltaPercent_computes_today_vs_yesterday() async {
        let client = StubClient(result: .success(stats(today: "120", yesterday: "100")))
        let vm = DashboardViewModel(client: client)
        await vm.refresh()

        XCTAssertEqual(vm.deltaPercent, Decimal(string: "20"))
    }

    func test_deltaPercent_is_nil_when_yesterday_is_zero() async {
        let client = StubClient(result: .success(stats(today: "120", yesterday: "0")))
        let vm = DashboardViewModel(client: client)
        await vm.refresh()

        XCTAssertNil(vm.deltaPercent)
    }
}

private final class StubClient: StatisticsClient, @unchecked Sendable {
    var result: Result<DashboardStats, StatsError>
    init(result: Result<DashboardStats, StatsError>) { self.result = result }
    func fetch(dateRange: DateRange) async throws -> DashboardStats {
        try result.get()
    }
}
