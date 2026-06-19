import XCTest
@testable import EsimplifiedKit

final class SessionStoreTests: XCTestCase {
    private func sampleSession() -> Session {
        Session(host: "https://live.esimplified.io",
                accessToken: "acc-1", refreshToken: "ref-1",
                expiresAt: Date(timeIntervalSince1970: 1_750_000_000),
                scopes: ["statistics:read", "order:read"],
                accountType: "human")
    }

    func test_inMemory_save_load_clear() throws {
        let store = InMemorySessionStore()
        XCTAssertNil(try store.load())
        try store.save(sampleSession())
        XCTAssertEqual(try store.load(), sampleSession())
        try store.clear()
        XCTAssertNil(try store.load())
    }

    func test_hasScope_matches_read_scope() {
        let s = sampleSession()
        XCTAssertTrue(s.hasScope("order"))
        XCTAssertFalse(s.hasScope("inventory"))
        // boundary: a non-read scope must not satisfy hasScope
        let writeOnly = Session(host: "h", accessToken: "a", refreshToken: "r",
                                expiresAt: Date(timeIntervalSince1970: 0),
                                scopes: ["order:write"], accountType: "human")
        XCTAssertFalse(writeOnly.hasScope("order"))
    }

    func test_inMemory_trusted_device_token_per_host() throws {
        let store = InMemorySessionStore()
        try store.saveTrustedDeviceToken("td-1", host: "https://a.example.com")
        XCTAssertEqual(try store.trustedDeviceToken(host: "https://a.example.com"), "td-1")
        XCTAssertNil(try store.trustedDeviceToken(host: "https://b.example.com"))
    }
}
