import XCTest
@testable import EsimPulseKit

private struct Widget: Decodable, Equatable { let id: Int; let name: String }

final class APIClientTests: XCTestCase {
    override func tearDown() { MockURLProtocol.handler = nil; super.tearDown() }

    private func makeClient() -> LiveAPIClient {
        LiveAPIClient(host: "https://live.esimplified.io", accessToken: "tok-9",
                      session: MockURLProtocol.makeSession())
    }

    func test_get_builds_url_query_and_bearer_then_decodes() async throws {
        var captured: URLRequest?
        MockURLProtocol.handler = { req in
            captured = req
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"id":7,"name":"a"}"#.utf8))
        }
        let w: Widget = try await makeClient().get("/api/widgets/1/", query: ["q": "x"], as: Widget.self)
        XCTAssertEqual(w, Widget(id: 7, name: "a"))
        XCTAssertEqual(captured?.url?.absoluteString,
                       "https://live.esimplified.io/api/widgets/1/?q=x")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer tok-9")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func test_get_maps_401_to_authExpired() async {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        await assertAPIError(.authExpired) { _ = try await self.makeClient().get("/x/", query: [:], as: Widget.self) }
    }

    func test_get_maps_404_to_notFound() async {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        await assertAPIError(.notFound) { _ = try await self.makeClient().get("/x/", query: [:], as: Widget.self) }
    }

    func test_get_maps_malformed_body_to_decoding() async {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("nope".utf8))
        }
        await assertAPIError(.decoding) { _ = try await self.makeClient().get("/x/", query: [:], as: Widget.self) }
    }

    func test_get_maps_transport_failure_to_unreachable() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await assertAPIError(.unreachable) { _ = try await self.makeClient().get("/x/", query: [:], as: Widget.self) }
    }

    private func assertAPIError(_ expected: APIError, _ block: () async throws -> Void,
                                file: StaticString = #filePath, line: UInt = #line) async {
        do { try await block(); XCTFail("expected \(expected)", file: file, line: line) }
        catch let e as APIError { XCTAssertEqual(e, expected, file: file, line: line) }
        catch { XCTFail("unexpected \(error)", file: file, line: line) }
    }
}
