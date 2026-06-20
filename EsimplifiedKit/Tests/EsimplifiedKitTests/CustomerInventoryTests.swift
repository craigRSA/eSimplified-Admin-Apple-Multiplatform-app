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

    func test_customer_displayName_falls_back_first_last_then_external_then_email() throws {
        func customer(_ json: String) throws -> Customer {
            try JSONDecoder().decode(Customer.self, from: Data(json.utf8))
        }
        // full_name wins
        XCTAssertEqual(try customer(#"{"full_name":"Ada Lovelace","first_name":"Ada","email":"a@x.io"}"#).displayName, "Ada Lovelace")
        // no full_name → first + last
        XCTAssertEqual(try customer(#"{"first_name":"Grace","last_name":"Hopper","email":"g@x.io"}"#).displayName, "Grace Hopper")
        // no name → external_reference
        XCTAssertEqual(try customer(#"{"external_reference":"EXT-9","email":"e@x.io"}"#).displayName, "EXT-9")
        // nothing but email
        XCTAssertEqual(try customer(#"{"email":"z@x.io"}"#).displayName, "z@x.io")
    }

    func test_customer_absent_is_active_defaults_to_inactive() throws {
        // The web treats a missing is_active as Disabled (is_active ?? false).
        let c = try JSONDecoder().decode(Customer.self, from: Data(#"{"customer_id":"c1","email":"a@x.io"}"#.utf8))
        XCTAssertFalse(c.isActive)
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
