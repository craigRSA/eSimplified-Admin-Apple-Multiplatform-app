import Foundation

/// Decodes a `Decimal` that may arrive as a JSON string (Django REST Framework's
/// default for decimals) or a JSON number. Money fields across the API use both
/// forms, so every model decodes them through this.
struct FlexibleDecimal: Decodable {
    let value: Decimal
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self), let dec = Decimal(string: string) {
            value = dec
        } else {
            value = try container.decode(Decimal.self)
        }
    }
}
