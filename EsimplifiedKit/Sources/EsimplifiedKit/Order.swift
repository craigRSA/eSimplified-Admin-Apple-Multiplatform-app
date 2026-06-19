import Foundation

/// One order from `/api/orders/` (a subset of the backend `OrderHistory` shape,
/// limited to what the list view shows).
public struct Order: Decodable, Identifiable, Equatable, Sendable {
    public var id: String { orderUUID }
    public let orderUUID: String
    public let orderNumber: String
    public let orderType: String
    public let packageName: String
    public let finalPrice: String
    public let purchaseCurrency: String
    public let currencySymbol: String?
    public let purchaseDate: String
    public let paymentStatus: String
    public let paymentMethod: String
    public let tenant: String
    public let customerEmail: String?
    public let customerName: String?

    private enum K: String, CodingKey {
        case tenant, customer
        case orderUUID = "order_uuid"
        case orderNumber = "order_number"
        case orderType = "order_type"
        case packageName = "package_name"
        case finalPrice = "final_price"
        case purchaseCurrency = "purchase_currency"
        case purchaseCurrencyObj = "purchase_currency_obj"
        case purchaseDate = "purchase_date"
        case paymentStatus = "payment_status"
        case paymentMethod = "payment_method"
    }
    private enum CurrencyKeys: String, CodingKey { case symbol }
    private struct Cust: Decodable { let email: String?; let full_name: String? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        func str(_ key: K, _ fallback: String = "") throws -> String {
            try c.decodeIfPresent(String.self, forKey: key) ?? fallback
        }
        orderUUID = try str(.orderUUID)
        orderNumber = try str(.orderNumber)
        orderType = try str(.orderType)
        packageName = try str(.packageName)
        finalPrice = try str(.finalPrice, "0")
        purchaseCurrency = try str(.purchaseCurrency)
        purchaseDate = try str(.purchaseDate)
        paymentStatus = try str(.paymentStatus)
        paymentMethod = try str(.paymentMethod)
        tenant = try str(.tenant)
        let cust = try c.decodeIfPresent(Cust.self, forKey: .customer)
        customerEmail = cust?.email
        customerName = cust?.full_name
        if let cur = try? c.nestedContainer(keyedBy: CurrencyKeys.self, forKey: .purchaseCurrencyObj) {
            currencySymbol = try cur.decodeIfPresent(String.self, forKey: .symbol)
        } else {
            currencySymbol = nil
        }
    }

    /// e.g. "$12.34" or "USD 12.34" — prefer the currency symbol, fall back to the code.
    public var priceDisplay: String {
        if let symbol = currencySymbol, !symbol.isEmpty { return "\(symbol)\(finalPrice)" }
        return purchaseCurrency.isEmpty ? finalPrice : "\(purchaseCurrency) \(finalPrice)"
    }
}

/// `/api/orders/` returns a paginated list grouped by tenant — each result holds
/// an `orders` array. This flattens them into one list.
public struct OrdersPage: Decodable, Sendable {
    public let count: Int
    public let orders: [Order]

    private enum K: String, CodingKey { case count, results }
    private struct Group: Decodable { let orders: [Order]? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        let groups = try c.decodeIfPresent([Group].self, forKey: .results) ?? []
        orders = groups.flatMap { $0.orders ?? [] }
    }
}
