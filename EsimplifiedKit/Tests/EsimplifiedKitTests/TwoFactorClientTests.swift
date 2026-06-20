import XCTest
@testable import EsimplifiedKit

final class TwoFactorClientTests: XCTestCase {
    override func tearDown() { MockURLProtocol.handler = nil; super.tearDown() }

    private func makeClient() -> LiveTwoFactorClient {
        LiveTwoFactorClient(host: "https://h.io", accessToken: "tok", session: MockURLProtocol.makeSession())
    }

    func test_status_reads_totp_enabled() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.absoluteString, "https://h.io/api/2fa/status/")
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
            XCTAssertEqual(req.url?.absoluteString, "https://h.io/api/2fa/setup/")
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"method":"totp","otpauth_url":"otpauth://totp/e?secret=ABC","secret":"ABC"}"#.utf8))
        }
        let setup = try await makeClient().beginSetup()
        XCTAssertEqual(setup, TOTPSetup(otpauthURL: "otpauth://totp/e?secret=ABC", secret: "ABC"))
    }

    func test_verify_posts_json_code_and_succeeds_on_2xx() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.absoluteString, "https://h.io/api/2fa/verify/")
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(Self.bodyJSON(req)?["code"] as? String, "123456")
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        try await makeClient().verify(code: "123456")
    }

    func test_disable_posts_json_code_to_correct_endpoint() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.absoluteString, "https://h.io/api/2fa/disable/")
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(Self.bodyJSON(req)?["code"] as? String, "654321")
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        try await makeClient().disable(code: "654321")
    }

    /// URLSession may deliver a request body to a URLProtocol via httpBodyStream
    /// rather than httpBody — read whichever is present, parsed as JSON.
    private static func bodyJSON(_ req: URLRequest) -> [String: Any]? {
        let data: Data?
        if let b = req.httpBody { data = b }
        else if let stream = req.httpBodyStream {
            stream.open(); defer { stream.close() }
            var acc = Data(); let size = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size); defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: size); if read <= 0 { break }; acc.append(buffer, count: read)
            }
            data = acc
        } else { data = nil }
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func test_verify_surfaces_real_status_on_non_2xx() async {
        // A wrong code (400) must surface the real status + server reason, not
        // a false "session expired".
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
             Data(#"{"detail":"invalid code"}"#.utf8))
        }
        do { try await makeClient().verify(code: "000000"); XCTFail("expected throw") }
        catch let APIError.requestFailed(status, message) {
            XCTAssertEqual(status, 400)
            XCTAssertEqual(message, #"{"detail":"invalid code"}"#)
        }
        catch { XCTFail("unexpected \(error)") }
    }

    func test_verify_throws_authExpired_on_401() async {
        // Only a true 401 signals an expired session.
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        do { try await makeClient().verify(code: "000000"); XCTFail("expected throw") }
        catch let e as APIError { XCTAssertEqual(e, .authExpired) }
        catch { XCTFail("unexpected \(error)") }
    }
}
