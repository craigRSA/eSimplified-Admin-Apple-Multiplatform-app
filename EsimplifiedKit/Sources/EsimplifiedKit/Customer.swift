import Foundation

/// A customer from `/api/customers/` (subset of the backend `Customer` shape).
public struct Customer: Decodable, Identifiable, Sendable {
    public let id: String
    public let customerId: String?
    public let email: String?
    public let fullName: String?
    public let firstName: String?
    public let lastName: String?
    public let externalReference: String?
    public let phoneNumber: String?
    public let isActive: Bool
    public let emailVerified: Bool
    public let created: String?

    private enum K: String, CodingKey {
        case email, created
        case fullName = "full_name"
        case firstName = "first_name"
        case lastName = "last_name"
        case externalReference = "external_reference"
        case phoneNumber = "phone_number"
        case isActive = "is_active"
        case emailVerified = "email_verified"
        case customerId = "customer_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        fullName = try c.decodeIfPresent(String.self, forKey: .fullName)
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName)
        externalReference = try c.decodeIfPresent(String.self, forKey: .externalReference)
        phoneNumber = try c.decodeIfPresent(String.self, forKey: .phoneNumber)
        // Match the web: an absent/false is_active reads as Inactive/Disabled
        // (the web detail uses `is_active ?? false`).
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        emailVerified = try c.decodeIfPresent(Bool.self, forKey: .emailVerified) ?? false
        created = try c.decodeIfPresent(String.self, forKey: .created)
        customerId = try c.decodeIfPresent(String.self, forKey: .customerId)
        id = customerId ?? email ?? UUID().uuidString
    }

    /// Display name mirroring the web's CustomerName / detail-header fallbacks:
    /// full_name → first + last → external_reference → email.
    public var displayName: String {
        if let fullName, !fullName.trimmingCharacters(in: .whitespaces).isEmpty { return fullName }
        let names = [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }
        if !names.isEmpty { return names.joined(separator: " ") }
        if let externalReference, !externalReference.isEmpty { return externalReference }
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
