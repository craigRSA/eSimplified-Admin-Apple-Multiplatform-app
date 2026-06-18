import XCTest
@testable import EsimPulseKit

final class StatisticsClientTests: XCTestCase {
    private let creds = Credentials(host: "https://admin.example.com", token: "tok-123")

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeClient() -> LiveStatisticsClient {
        LiveStatisticsClient(credentials: creds, session: MockURLProtocol.makeSession())
    }

    func test_fetch_builds_correct_url_and_auth_header() async throws {
        var captured: URLRequest?
        MockURLProtocol.handler = { request in
            captured = request
            let body = #"{"revenue_today":"1.00","revenue_yesterday":"1.00","current":{"success_orders":0,"revenue_per_date":[]}}"#
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(body.utf8))
        }

        _ = try await makeClient().fetch(dateRange: .last7Days)

        XCTAssertEqual(captured?.url?.absoluteString,
                       "https://admin.example.com/api/statistics/?date_range=last_7_days")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer tok-123")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func test_fetch_returns_decoded_stats_on_200() async throws {
        MockURLProtocol.handler = { request in
            let body = #"{"revenue_today":"1523.45","revenue_yesterday":"1402.10","current":{"success_orders":87,"revenue_per_date":[]}}"#
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(body.utf8))
        }

        let stats = try await makeClient().fetch(dateRange: .last7Days)

        XCTAssertEqual(stats.revenueToday, Decimal(string: "1523.45"))
    }

    func test_fetch_maps_401_to_authExpired() async {
        MockURLProtocol.handler = { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }

        await assertThrows(.authExpired) { _ = try await self.makeClient().fetch(dateRange: .today) }
    }

    func test_fetch_maps_malformed_body_to_noData() async {
        MockURLProtocol.handler = { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("not json".utf8))
        }

        await assertThrows(.noData) { _ = try await self.makeClient().fetch(dateRange: .today) }
    }

    func test_fetch_maps_transport_failure_to_unreachable() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        await assertThrows(.unreachable) { _ = try await self.makeClient().fetch(dateRange: .today) }
    }

    private func assertThrows(_ expected: StatsError,
                              _ block: () async throws -> Void,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await block()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as StatsError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }
}
