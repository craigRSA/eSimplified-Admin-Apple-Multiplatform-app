import XCTest
@testable import EsimplifiedKit

final class AuthClientTests: XCTestCase {
    override func tearDown() { MockURLProtocol.handler = nil; super.tearDown() }

    private func makeClient() -> LiveAuthClient {
        LiveAuthClient(clientID: "cid", clientSecret: "csec", session: MockURLProtocol.makeSession())
    }

    private func respond(_ json: String, _ status: Int = 200) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        { req in (HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(json.utf8)) }
    }

    func test_login_success_returns_session_with_scopes() async throws {
        var captured: URLRequest?
        MockURLProtocol.handler = { req in
            captured = req
            let json = #"{"access_token":"acc","refresh_token":"ref","token_type":"Bearer","expires_in":3600,"scope":"statistics:read order:read","account_type":"human"}"#
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        let result = try await makeClient().login(username: "u", password: "p",
                                                   host: "https://live.esimplified.io", trustedDeviceToken: nil)
        guard case let .session(s) = result else { return XCTFail("expected session") }
        XCTAssertEqual(s.accessToken, "acc")
        XCTAssertEqual(s.scopes, ["statistics:read", "order:read"])
        XCTAssertEqual(s.accountType, "human")
        XCTAssertEqual(captured?.url?.absoluteString, "https://live.esimplified.io/auth/token/")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"),
                       "Basic " + Data("cid:csec".utf8).base64EncodedString())
    }

    func test_login_requires_2fa_returns_needs2FA() async throws {
        MockURLProtocol.handler = respond(#"{"requires_2fa":true,"2fa_token":"tok-2fa"}"#)
        let result = try await makeClient().login(username: "u", password: "p",
                                                  host: "https://h.io", trustedDeviceToken: nil)
        XCTAssertEqual(result, .needs2FA(token: "tok-2fa"))
    }

    func test_login_sends_trusted_device_header_when_present() async throws {
        var captured: URLRequest?
        MockURLProtocol.handler = { req in
            captured = req
            let json = #"{"access_token":"a","refresh_token":"r","expires_in":60,"scope":"order:read","account_type":"human"}"#
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        _ = try await makeClient().login(username: "u", password: "p", host: "https://h.io", trustedDeviceToken: "td-7")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "X-Trusted-Device"), "td-7")
    }

    func test_verify2FA_sends_json_with_correct_fields_and_returns_session() async throws {
        var captured: URLRequest?
        MockURLProtocol.handler = { req in
            captured = req
            let json = #"{"access_token":"a2","refresh_token":"r2","expires_in":3600,"scope":"order:read","account_type":"human","trusted_device_token":"td-new"}"#
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        let (s, td) = try await makeClient().verify2FA(host: "https://h.io", twoFAToken: "tok", code: "123456", rememberDevice: true)
        XCTAssertEqual(s.accessToken, "a2")
        XCTAssertEqual(td, "td-new")
        XCTAssertEqual(captured?.url?.absoluteString, "https://h.io/auth/token/2fa/")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        // The backend expects a JSON body with these exact field names.
        let body = try XCTUnwrap(Self.bodyJSON(captured))
        XCTAssertEqual(body["two_fa_token"] as? String, "tok")
        XCTAssertEqual(body["code"] as? String, "123456")
        XCTAssertEqual(body["remember_device"] as? Bool, true)
    }

    private static func bodyJSON(_ req: URLRequest?) -> [String: Any]? {
        guard let req else { return nil }
        let data: Data?
        if let b = req.httpBody { data = b }
        else if let stream = req.httpBodyStream {
            stream.open(); defer { stream.close() }
            var acc = Data(); let size = 4096
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: size); defer { buf.deallocate() }
            while stream.hasBytesAvailable {
                let n = stream.read(buf, maxLength: size); if n <= 0 { break }; acc.append(buf, count: n)
            }
            data = acc
        } else { data = nil }
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func test_refresh_returns_new_session() async throws {
        MockURLProtocol.handler = respond(#"{"access_token":"a3","refresh_token":"r3","expires_in":3600,"scope":"order:read","account_type":"human"}"#)
        let s = try await makeClient().refresh(host: "https://h.io", refreshToken: "r2")
        XCTAssertEqual(s.accessToken, "a3")
    }

    func test_refresh_omits_basic_auth_and_sends_client_creds_in_body() async throws {
        // OAuth2 confidential-client refresh: no Basic header; creds in the form
        // body (mirrors the web client). Login keeps Basic — verified separately.
        var captured: URLRequest?
        MockURLProtocol.handler = { req in
            captured = req
            let json = #"{"access_token":"a3","refresh_token":"r3","expires_in":3600,"scope":"order:read","account_type":"human"}"#
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        _ = try await makeClient().refresh(host: "https://h.io", refreshToken: "r2")
        XCTAssertEqual(captured?.url?.absoluteString, "https://h.io/auth/token/")
        XCTAssertNil(captured?.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(String(data: XCTUnwrap(Self.bodyData(captured)), encoding: .utf8))
        XCTAssertTrue(body.contains("grant_type=refresh_token"), body)
        XCTAssertTrue(body.contains("refresh_token=r2"), body)
        XCTAssertTrue(body.contains("client_id=cid"), body)
        XCTAssertTrue(body.contains("client_secret=csec"), body)
    }

    private static func bodyData(_ req: URLRequest?) -> Data? {
        guard let req else { return nil }
        if let b = req.httpBody { return b }
        guard let stream = req.httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var acc = Data(); let size = 4096
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: size); defer { buf.deallocate() }
        while stream.hasBytesAvailable {
            let n = stream.read(buf, maxLength: size); if n <= 0 { break }; acc.append(buf, count: n)
        }
        return acc
    }

    func test_formEncode_percent_encodes_special_characters() {
        // %, @, space, and + must all be encoded so credentials survive intact.
        XCTAssertEqual(LiveAuthClient.formEncode(["a": "x%y@z d+e"]), "a=x%25y%40z%20d%2Be")
        XCTAssertEqual(LiveAuthClient.formEncode(["grant_type": "password"]), "grant_type=password")
    }

    func test_password_leading_space_is_preserved_not_trimmed() async throws {
        // Hard rule: a user's password may begin with a space and must never be
        // trimmed. Guard both layers — the encoder, and the login call site (a
        // `.trimmingCharacters` added before formEncode would slip past unit tests
        // that only use trivial passwords).
        XCTAssertEqual(LiveAuthClient.formEncode(["password": " p"]), "password=%20p")

        var captured: URLRequest?
        MockURLProtocol.handler = { req in
            captured = req
            let json = #"{"access_token":"a","refresh_token":"r","expires_in":60,"scope":"order:read","account_type":"human"}"#
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        _ = try await makeClient().login(username: "u", password: " spacey",
                                         host: "https://h.io", trustedDeviceToken: nil)
        let body = try XCTUnwrap(String(data: XCTUnwrap(Self.bodyData(captured)), encoding: .utf8))
        XCTAssertTrue(body.contains("password=%20spacey"), body)
    }

    func test_login_failure_surfaces_server_status_and_message() async {
        MockURLProtocol.handler = respond(#"{"error":"invalid_grant","error_description":"Invalid credentials given."}"#, 400)
        do {
            _ = try await makeClient().login(username: "u", password: "p", host: "https://h.io", trustedDeviceToken: nil)
            XCTFail("expected throw")
        } catch let e as APIError {
            XCTAssertEqual(e, .requestFailed(status: 400, serverMessage: "Invalid credentials given."))
        }
        catch { XCTFail("unexpected \(error)") }
    }
}
