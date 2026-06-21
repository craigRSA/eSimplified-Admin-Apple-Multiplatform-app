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

    func test_decode_handles_numeric_order_number() throws {
        // Live responses send order_number as a JSON number (133831), not the
        // string the web's TS type claims. Decoding the page must not throw.
        let json = """
        {
          "count": 2,
          "results": [
            {
              "total": 2, "total_purchases": 1, "total_topups": 1,
              "orders": [
                {
                  "order_uuid": "86d7", "order_number": 133831, "order_type": "BUY",
                  "package_name": "Algeria 1 GB 7 Days", "final_price": "4.25",
                  "final_price_local": "4.25", "purchase_currency": "US $",
                  "purchase_currency_obj": {"symbol":"US $","iso":"USD"},
                  "purchase_country": null,
                  "purchase_date": "2026-06-03T08:00:05.665816Z",
                  "payment_status": "refunded", "payment_method": "agent_payment",
                  "tenant": "knowroaming",
                  "customer": {"email":"x@x.io","full_name":"Xolani Khumalo","customer_id":"1f99"}
                },
                {
                  "order_uuid": "c0d5", "order_number": 115051, "order_type": "BUY",
                  "package_name": "UAE 1 GB 7 Days", "final_price": "3.89",
                  "purchase_currency": "US $",
                  "purchase_country": {"iso":"ZA","name":"South Africa"},
                  "purchase_date": "2026-04-09T07:48:53.515496Z",
                  "payment_status": "refunded", "payment_method": "stripe_intent",
                  "tenant": "knowroaming", "customer": {"email":"x@x.io"}
                }
              ]
            }
          ]
        }
        """
        let page = try JSONDecoder().decode(OrdersPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.count, 2)
        XCTAssertEqual(page.orders.count, 2)
        XCTAssertEqual(page.orders[0].orderNumber, "133831")
        XCTAssertEqual(page.orders[0].purchaseCountry, nil)
        XCTAssertEqual(page.orders[1].orderNumber, "115051")
        XCTAssertEqual(page.orders[1].purchaseCountry, "South Africa")
    }

    func test_decode_tolerates_empty() throws {
        let page = try JSONDecoder().decode(OrdersPage.self, from: Data("{}".utf8))
        XCTAssertEqual(page.count, 0)
        XCTAssertEqual(page.orders, [])
    }
}
