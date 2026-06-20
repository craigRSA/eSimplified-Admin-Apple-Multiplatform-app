import XCTest
@testable import EsimplifiedKit

/// Provider that serves one stale token, then a refreshed one after a 401.
private actor SequenceProvider: AccessTokenProviding {
    private var refreshed = false
    func validAccessToken() async throws -> String { "stale" }
    func refreshedAccessToken(after staleToken: String) async throws -> String {
        refreshed = true; return "fresh"
    }
}

final class APIClientRefreshTests: XCTestCase {
    override func tearDown() { MockURLProtocol.handler = nil; super.tearDown() }

    func test_staticProvider_returnsToken_andCannotRefresh() async throws {
        let p = StaticTokenProvider("tok-1")
        let v = try await p.validAccessToken()
        XCTAssertEqual(v, "tok-1")
        do { _ = try await p.refreshedAccessToken(after: "tok-1"); XCTFail("expected authExpired") }
        catch { XCTAssertEqual(error as? APIError, .authExpired) }
    }

    func test_staticProvider_emptyToken_throwsAuthExpired() async {
        let p = StaticTokenProvider("")
        do { _ = try await p.validAccessToken(); XCTFail("expected authExpired") }
        catch { XCTAssertEqual(error as? APIError, .authExpired) }
    }

    func test_get_retriesOnceAfter401_withRefreshedToken() async throws {
        // First response 401, second 200 — assert the retry carries "Bearer fresh".
        var seenAuthHeaders: [String] = []
        MockURLProtocol.handler = { request in
            seenAuthHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
            let code = seenAuthHeaders.count == 1 ? 401 : 200
            let body = code == 200 ? Data(#"{"ok":true}"#.utf8) : Data()
            let resp = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
        let client = LiveAPIClient(host: "https://h", tokenProvider: SequenceProvider(),
                                   session: MockURLProtocol.makeSession())
        struct OK: Decodable { let ok: Bool }
        let result = try await client.get("/api/x/", query: [:], as: OK.self)
        XCTAssertTrue(result.ok)
        XCTAssertEqual(seenAuthHeaders, ["Bearer stale", "Bearer fresh"])
    }

    func test_get_throwsAuthExpired_whenRetryAlso401() async {
        MockURLProtocol.handler = { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        let client = LiveAPIClient(host: "https://h", tokenProvider: SequenceProvider(),
                                   session: MockURLProtocol.makeSession())
        struct OK: Decodable { let ok: Bool }
        do { _ = try await client.get("/api/x/", query: [:], as: OK.self); XCTFail("expected authExpired") }
        catch { XCTAssertEqual(error as? APIError, .authExpired) }
    }
}
