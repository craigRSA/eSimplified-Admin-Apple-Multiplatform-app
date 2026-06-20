import XCTest
@testable import EsimplifiedKit

final class APIClientRefreshTests: XCTestCase {
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
}
