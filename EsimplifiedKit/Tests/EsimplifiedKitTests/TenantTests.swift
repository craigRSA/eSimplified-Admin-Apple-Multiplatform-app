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
}
