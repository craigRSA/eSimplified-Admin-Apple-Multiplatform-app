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
    public let paymentReference: String?
    public let signInProvider: String?
    public let uniqueReferralCode: String?
    public let marketingEmail: Bool?
    public let marketingPush: Bool?
    public let accountEmail: Bool?
    public let accountSms: Bool?
    public let accountPush: Bool?
    public let purchaseEmail: Bool?
    public let purchasePush: Bool?

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
        case paymentReference = "payment_reference"
        case signInProvider = "sign_in_as_provider"
        case uniqueReferralCode = "unique_referral_code"
        case marketingEmail = "marketing_email"
        case marketingPush = "marketing_push"
        case accountEmail = "account_email"
        case accountSms = "account_sms"
        case accountPush = "account_push"
        case purchaseEmail = "purchase_email"
        case purchasePush = "purchase_push"
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
        paymentReference = try c.decodeIfPresent(String.self, forKey: .paymentReference)
        signInProvider = try c.decodeIfPresent(String.self, forKey: .signInProvider)
        uniqueReferralCode = try c.decodeIfPresent(String.self, forKey: .uniqueReferralCode)
        marketingEmail = try c.decodeIfPresent(Bool.self, forKey: .marketingEmail)
        marketingPush = try c.decodeIfPresent(Bool.self, forKey: .marketingPush)
        accountEmail = try c.decodeIfPresent(Bool.self, forKey: .accountEmail)
        accountSms = try c.decodeIfPresent(Bool.self, forKey: .accountSms)
        accountPush = try c.decodeIfPresent(Bool.self, forKey: .accountPush)
        purchaseEmail = try c.decodeIfPresent(Bool.self, forKey: .purchaseEmail)
        purchasePush = try c.decodeIfPresent(Bool.self, forKey: .purchasePush)
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

    /// Notification preferences grouped for read-only display: (group, [(channel, on)]).
    /// Channels absent from the response are omitted.
    public var notificationGroups: [(String, [(String, Bool)])] {
        func group(_ name: String, _ pairs: [(String, Bool?)]) -> (String, [(String, Bool)])? {
            let present = pairs.compactMap { label, value in value.map { (label, $0) } }
            return present.isEmpty ? nil : (name, present)
        }
        return [
            group("Marketing", [("Email", marketingEmail), ("Push", marketingPush)]),
            group("Account", [("Email", accountEmail), ("SMS", accountSms), ("Push", accountPush)]),
            group("Purchase", [("Email", purchaseEmail), ("Push", purchasePush)]),
        ].compactMap { $0 }
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
