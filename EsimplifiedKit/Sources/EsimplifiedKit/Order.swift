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
    public let finalPriceLocal: String
    public let purchaseCurrency: String
    public let currencySymbol: String?
    public let discountCode: String?
    public let purchaseCountry: String?
    public let purchaseDate: String
    public let paymentStatus: String
    public let paymentMethod: String
    public let tenant: String
    public let iccid: String?
    public let customerId: String?
    public let customerEmail: String?
    public let customerName: String?
    public let purchasePrice: String
    public let refundStatus: String?

    private enum K: String, CodingKey {
        case tenant, customer, iccid
        case orderUUID = "order_uuid"
        case orderNumber = "order_number"
        case orderType = "order_type"
        case packageName = "package_name"
        case finalPrice = "final_price"
        case finalPriceLocal = "final_price_local"
        case purchaseCurrency = "purchase_currency"
        case purchaseCurrencyObj = "purchase_currency_obj"
        case discountCode = "discount_code"
        case purchaseCountry = "purchase_country"
        case purchaseDate = "purchase_date"
        case paymentStatus = "payment_status"
        case paymentMethod = "payment_method"
        case purchasePrice = "purchase_price"
        case refundRequest = "refund_request"
    }
    private enum RefundK: String, CodingKey { case refundStatus = "refund_status" }
    private enum CurrencyKeys: String, CodingKey { case symbol }
    private enum CountryKeys: String, CodingKey { case name }
    private struct Cust: Decodable { let email: String?; let full_name: String?; let customer_id: String? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        func str(_ key: K, _ fallback: String = "") throws -> String {
            try c.decodeIfPresent(String.self, forKey: key) ?? fallback
        }
        // order_number comes over the wire as a JSON number, not the string the
        // web's TS type claims — accept either or the whole page fails to decode.
        func numericOrString(_ key: K) -> String {
            if let s = try? c.decode(String.self, forKey: key) { return s }
            if let i = try? c.decode(Int.self, forKey: key) { return String(i) }
            return ""
        }
        orderUUID = try str(.orderUUID)
        orderNumber = numericOrString(.orderNumber)
        orderType = try str(.orderType)
        packageName = try str(.packageName)
        finalPrice = try str(.finalPrice, "0")
        finalPriceLocal = try str(.finalPriceLocal)
        purchaseCurrency = try str(.purchaseCurrency)
        discountCode = try c.decodeIfPresent(String.self, forKey: .discountCode).flatMap { $0.isEmpty ? nil : $0 }
        purchaseDate = try str(.purchaseDate)
        paymentStatus = try str(.paymentStatus)
        paymentMethod = try str(.paymentMethod)
        // purchase_price (pre-discount) is money — usually a string, occasionally a number.
        if let s = try? c.decode(String.self, forKey: .purchasePrice) {
            purchasePrice = s
        } else if let d = try? c.decode(FlexibleDecimal.self, forKey: .purchasePrice) {
            purchasePrice = NSDecimalNumber(decimal: d.value).stringValue
        } else {
            purchasePrice = ""
        }
        // refund_request is an object or null.
        if let r = try? c.nestedContainer(keyedBy: RefundK.self, forKey: .refundRequest) {
            refundStatus = try? r.decodeIfPresent(String.self, forKey: .refundStatus)
        } else {
            refundStatus = nil
        }
        tenant = try str(.tenant)
        iccid = try c.decodeIfPresent(String.self, forKey: .iccid)
        let cust = try c.decodeIfPresent(Cust.self, forKey: .customer)
        customerEmail = cust?.email
        customerName = cust?.full_name
        customerId = cust?.customer_id
        if let cur = try? c.nestedContainer(keyedBy: CurrencyKeys.self, forKey: .purchaseCurrencyObj) {
            currencySymbol = try cur.decodeIfPresent(String.self, forKey: .symbol)
        } else {
            currencySymbol = nil
        }
        // purchase_country is a Country object on the wire; we only need its name.
        if let country = try? c.nestedContainer(keyedBy: CountryKeys.self, forKey: .purchaseCountry) {
            purchaseCountry = try country.decodeIfPresent(String.self, forKey: .name)
        } else {
            purchaseCountry = nil
        }
    }

    /// e.g. "$12.34" or "USD 12.34" — prefer the currency symbol, fall back to the code.
    public var priceDisplay: String {
        if let symbol = currencySymbol, !symbol.isEmpty { return "\(symbol)\(finalPrice)" }
        return purchaseCurrency.isEmpty ? finalPrice : "\(purchaseCurrency) \(finalPrice)"
    }

    /// USD price as the web shows it: always `$` + `final_price`.
    public var usdPriceDisplay: String { "$\(finalPrice)" }

    /// Local-currency price, or nil when the order was billed in USD (web blanks
    /// the "Price (Local)" column when `purchase_currency` is "US $").
    public var localPriceDisplay: String? {
        guard purchaseCurrency != "US $", !purchaseCurrency.isEmpty, !finalPriceLocal.isEmpty else { return nil }
        return "\(purchaseCurrency) \(finalPriceLocal)"
    }

    /// Given free — web shows "Complimentary" instead of a price.
    public var isComplimentary: Bool { paymentMethod == "complimentary" }

    /// Pre-discount USD price, shown struck-through when a discount applied and it differs.
    public var struckPriceDisplay: String? {
        guard discountCode != nil, !purchasePrice.isEmpty, purchasePrice != finalPrice else { return nil }
        return "$\(purchasePrice)"
    }

    /// Short refund-status label matching the web's order list, or nil.
    public var refundLabel: String? {
        switch refundStatus {
        case "requested", "awaiting_s2s": return "Refund Requested"
        case "cancelled": return "Refund Cancelled"
        default: return nil
        }
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
