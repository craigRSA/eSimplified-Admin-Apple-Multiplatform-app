import XCTest
@testable import EsimplifiedKit

final class OrderTests: XCTestCase {
    func test_decode_flattens_tenant_grouped_pages() throws {
        let json = """
        {
          "count": 2,
          "results": [
            {
              "tenant": "acme",
              "orders": [
                {
                  "order_uuid": "u1", "order_number": "ORD-1", "order_type": "BUY",
                  "package_name": "5GB Europe", "final_price": "12.34",
                  "final_price_local": "229.50", "discount_code": "SUMMER20",
                  "purchase_country": {"name": "South Africa"},
                  "purchase_currency": "R", "purchase_currency_obj": {"iso":"ZAR","symbol":"R"},
                  "purchase_date": "2026-06-19T10:00:00Z", "payment_status": "success",
                  "tenant": "acme", "customer": {"email":"a@x.io","full_name":"Ada Lovelace"}
                }
              ]
            },
            {
              "tenant": "globex",
              "orders": [
                {
                  "order_uuid": "u2", "order_number": "ORD-2", "order_type": "TOP UP",
                  "package_name": "1GB Asia", "final_price": "5.00",
                  "purchase_currency": "EUR",
                  "purchase_date": "2026-06-18T09:00:00Z", "payment_status": "refunded",
                  "tenant": "globex", "customer": {"email":"b@x.io"}
                }
              ]
            }
          ]
        }
        """
        let page = try JSONDecoder().decode(OrdersPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.count, 2)
        XCTAssertEqual(page.orders.count, 2)
        let first = page.orders[0]
        XCTAssertEqual(first.orderNumber, "ORD-1")
        XCTAssertEqual(first.packageName, "5GB Europe")
        XCTAssertEqual(first.priceDisplay, "R12.34")
        XCTAssertEqual(first.usdPriceDisplay, "$12.34")
        XCTAssertEqual(first.localPriceDisplay, "R 229.50")
        XCTAssertEqual(first.discountCode, "SUMMER20")
        XCTAssertEqual(first.purchaseCountry, "South Africa")
        XCTAssertEqual(first.paymentStatus, "success")
        XCTAssertEqual(first.customerEmail, "a@x.io")
        XCTAssertEqual(first.customerName, "Ada Lovelace")
        let second = page.orders[1]
        XCTAssertEqual(second.priceDisplay, "EUR 5.00") // no symbol obj → code fallback
        XCTAssertEqual(second.usdPriceDisplay, "$5.00")
        XCTAssertNil(second.localPriceDisplay) // no final_price_local → blank
        XCTAssertNil(second.discountCode)
        XCTAssertNil(second.purchaseCountry)
        XCTAssertNil(second.customerName)
    }

    func test_decode_tolerates_empty() throws {
        let page = try JSONDecoder().decode(OrdersPage.self, from: Data("{}".utf8))
        XCTAssertEqual(page.count, 0)
        XCTAssertEqual(page.orders, [])
    }
}
