import XCTest
@testable import EsimPulseKit

final class CredentialStoreTests: XCTestCase {
    func test_inMemory_save_then_load_returns_same_credentials() throws {
        let store = InMemoryCredentialStore()
        let creds = Credentials(host: "https://admin.example.com", token: "abc123")

        try store.save(creds)

        XCTAssertEqual(try store.load(), creds)
    }

    func test_inMemory_load_when_empty_returns_nil() throws {
        let store = InMemoryCredentialStore()
        XCTAssertNil(try store.load())
    }

    func test_inMemory_clear_removes_credentials() throws {
        let store = InMemoryCredentialStore()
        try store.save(Credentials(host: "h", token: "t"))

        try store.clear()

        XCTAssertNil(try store.load())
    }
}
