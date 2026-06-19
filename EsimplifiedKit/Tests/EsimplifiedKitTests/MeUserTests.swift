import XCTest
@testable import EsimplifiedKit

final class MeUserTests: XCTestCase {
    func test_decode_me_user() throws {
        let json = """
        {"id":1,"username":"craigp","email":"craig@esimplified.io","first_name":"Craig","last_name":"Perkel",
         "is_staff":true,"is_active":true,"is_superuser":false,"account_type":"human",
         "extra_scopes":[],"all_tenant_access":true,
         "effective_scopes":["statistics:read","order:read"],
         "group_assignments":[],
         "tenants":[{"name":"Acme","schema_name":"acme"},{"name":"Globex","schema_name":"globex"}]}
        """
        let me = try JSONDecoder().decode(MeUser.self, from: Data(json.utf8))
        XCTAssertEqual(me.displayName, "Craig Perkel")
        XCTAssertEqual(me.email, "craig@esimplified.io")
        XCTAssertEqual(me.accountType, "human")
        XCTAssertTrue(me.isStaff)
        XCTAssertTrue(me.allTenantAccess)
        XCTAssertEqual(me.effectiveScopes, ["statistics:read", "order:read"])
        XCTAssertEqual(me.tenantNames, ["Acme", "Globex"])
    }

    func test_displayName_falls_back_to_username() throws {
        let me = try JSONDecoder().decode(MeUser.self, from: Data(#"{"username":"svc","first_name":"","last_name":""}"#.utf8))
        XCTAssertEqual(me.displayName, "svc")
    }
}
