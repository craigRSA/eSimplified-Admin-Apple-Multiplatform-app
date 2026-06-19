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

    func test_verify2FA_returns_session_and_trusted_token() async throws {
        MockURLProtocol.handler = respond(#"{"access_token":"a2","refresh_token":"r2","expires_in":3600,"scope":"order:read","account_type":"human","trusted_device_token":"td-new"}"#)
        let (s, td) = try await makeClient().verify2FA(host: "https://h.io", twoFAToken: "tok", code: "123456", rememberDevice: true)
        XCTAssertEqual(s.accessToken, "a2")
        XCTAssertEqual(td, "td-new")
    }

    func test_refresh_returns_new_session() async throws {
        MockURLProtocol.handler = respond(#"{"access_token":"a3","refresh_token":"r3","expires_in":3600,"scope":"order:read","account_type":"human"}"#)
        let s = try await makeClient().refresh(host: "https://h.io", refreshToken: "r2")
        XCTAssertEqual(s.accessToken, "a3")
    }

    func test_formEncode_percent_encodes_special_characters() {
        // %, @, space, and + must all be encoded so credentials survive intact.
        XCTAssertEqual(LiveAuthClient.formEncode(["a": "x%y@z d+e"]), "a=x%25y%40z%20d%2Be")
        XCTAssertEqual(LiveAuthClient.formEncode(["grant_type": "password"]), "grant_type=password")
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
