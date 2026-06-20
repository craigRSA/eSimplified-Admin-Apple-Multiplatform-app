import XCTest
@testable import EsimplifiedKit

final class TenantTests: XCTestCase {
    func test_decode_flat_tenant_list_and_skips_blank_schemas() throws {
        let json = """
        {"count":2,"results":[
          {"name":"KnowRoaming","schema_name":"knowroaming"},
          {"name":"FNB eSIMs","schema_name":"fnb"},
          {"name":"Broken","schema_name":""}
        ]}
        """
        let page = try JSONDecoder().decode(TenantsPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.tenants.count, 2)
        XCTAssertEqual(page.tenants.first, Tenant(name: "KnowRoaming", schemaName: "knowroaming"))
        XCTAssertEqual(page.tenants.first?.id, "knowroaming")
    }

    func test_decode_logo_small_from_settings() throws {
        let json = """
        {"count":3,"results":[
          {"name":"FNB","schema_name":"fnb","settings":{"logo_small":"https://cdn.example.com/fnb.png"}},
          {"name":"GCash","schema_name":"gcash","settings":{"logo_small":null}},
          {"name":"Plain","schema_name":"plain"}
        ]}
        """
        let page = try JSONDecoder().decode(TenantsPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.tenants.count, 3)
        XCTAssertEqual(page.tenants[0].logoSmall, URL(string: "https://cdn.example.com/fnb.png"))
        XCTAssertNil(page.tenants[1].logoSmall, "explicit null logo_small → nil")
        XCTAssertNil(page.tenants[2].logoSmall, "absent settings → nil")
    }
}
