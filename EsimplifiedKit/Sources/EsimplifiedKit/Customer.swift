import Foundation

/// A customer from `/api/customers/` (subset of the backend `Customer` shape).
public struct Customer: Decodable, Identifiable, Sendable {
    public let id: String
    public let email: String?
    public let fullName: String?
    public let phoneNumber: String?
    public let isActive: Bool
    public let created: String?

    private enum K: String, CodingKey {
        case email, created
        case fullName = "full_name"
        case phoneNumber = "phone_number"
        case isActive = "is_active"
        case customerId = "customer_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        fullName = try c.decodeIfPresent(String.self, forKey: .fullName)
        phoneNumber = try c.decodeIfPresent(String.self, forKey: .phoneNumber)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        created = try c.decodeIfPresent(String.self, forKey: .created)
        let customerId = try c.decodeIfPresent(String.self, forKey: .customerId)
        id = customerId ?? email ?? UUID().uuidString
    }

    public var displayName: String {
        if let fullName, !fullName.isEmpty { return fullName }
        return email ?? "—"
    }
}

/// `/api/customers/` is paginated and grouped by tenant; flatten `results[].customers`.
public struct CustomersPage: Decodable, Sendable {
    public let count: Int
    public let customers: [Customer]

    private enum K: String, CodingKey { case count, results }
    private struct Group: Decodable { let customers: [Customer]? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        let groups = try c.decodeIfPresent([Group].self, forKey: .results) ?? []
        customers = groups.flatMap { $0.customers ?? [] }
    }
}
