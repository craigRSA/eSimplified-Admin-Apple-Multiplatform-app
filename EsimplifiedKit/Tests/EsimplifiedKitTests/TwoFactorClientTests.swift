import XCTest
@testable import EsimplifiedKit

final class TwoFactorClientTests: XCTestCase {
    override func tearDown() { MockURLProtocol.handler = nil; super.tearDown() }

    private func makeClient() -> LiveTwoFactorClient {
        LiveTwoFactorClient(host: "https://h.io", accessToken: "tok", session: MockURLProtocol.makeSession())
    }

    func test_status_reads_totp_enabled() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.absoluteString, "https://h.io/2fa/status/")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"totp_enabled":true}"#.utf8))
        }
        let enabled = try await makeClient().status()
        XCTAssertTrue(enabled)
    }

    func test_beginSetup_returns_otpauth_url_and_secret() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.url?.absoluteString, "https://h.io/2fa/setup/")
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"method":"totp","otpauth_url":"otpauth://totp/e?secret=ABC","secret":"ABC"}"#.utf8))
        }
        let setup = try await makeClient().beginSetup()
        XCTAssertEqual(setup, TOTPSetup(otpauthURL: "otpauth://totp/e?secret=ABC", secret: "ABC"))
    }

    func test_verify_posts_code_and_succeeds_on_2xx() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.absoluteString, "https://h.io/2fa/verify/")
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(Self.bodyString(req), "code=123456")
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        try await makeClient().verify(code: "123456")
    }

    func test_disable_posts_code_to_correct_endpoint() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.absoluteString, "https://h.io/2fa/disable/")
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(Self.bodyString(req), "code=654321")
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        try await makeClient().disable(code: "654321")
    }

    /// URLSession may deliver a request body to a URLProtocol via httpBodyStream
    /// rather than httpBody — read whichever is present.
    private static func bodyString(_ req: URLRequest) -> String? {
        if let data = req.httpBody { return String(data: data, encoding: .utf8) }
        guard let stream = req.httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data()
        let size = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return String(data: data, encoding: .utf8)
    }

    func test_verify_throws_authExpired_on_non_2xx() async {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        do { try await makeClient().verify(code: "000000"); XCTFail("expected throw") }
        catch let e as APIError { XCTAssertEqual(e, .authExpired) }
        catch { XCTFail("unexpected \(error)") }
    }
}
