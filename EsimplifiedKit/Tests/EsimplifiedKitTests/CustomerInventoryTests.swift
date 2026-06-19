import XCTest
@testable import EsimplifiedKit

final class CustomerInventoryTests: XCTestCase {
    func test_customers_page_flattens_groups() throws {
        let json = """
        {"count":3,"results":[
          {"tenant":"acme","customers":[
            {"customer_id":"c1","email":"a@x.io","full_name":"Ada","phone_number":"+1","is_active":true},
            {"email":"b@x.io","is_active":false}
          ]},
          {"tenant":"globex","customers":[{"customer_id":"c3","email":"c@x.io"}]}
        ]}
        """
        let page = try JSONDecoder().decode(CustomersPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.count, 3)
        XCTAssertEqual(page.customers.count, 3)
        XCTAssertEqual(page.customers[0].displayName, "Ada")
        XCTAssertEqual(page.customers[0].id, "c1")
        XCTAssertEqual(page.customers[1].displayName, "b@x.io") // no full_name → email
        XCTAssertFalse(page.customers[1].isActive)
    }

    func test_inventory_decodes_totals_and_imsis() throws {
        let json = """
        {"total_esims":1000,"total_unassigned_esims":400,"total_pending_esims":100,"total_assigned_esims":500,
         "imsis":[{"imsi":"123","unassigned_count":4,"pending_count":1,"assigned_count":5}]}
        """
        let inv = try JSONDecoder().decode(Inventory.self, from: Data(json.utf8))
        XCTAssertEqual(inv.totalEsims, 1000)
        XCTAssertEqual(inv.totalAssigned, 500)
        XCTAssertEqual(inv.imsis.count, 1)
        XCTAssertEqual(inv.imsis[0].imsi, "123")
        XCTAssertEqual(inv.imsis[0].assignedCount, 5)
    }
}
