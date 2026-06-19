import Foundation

/// The signed-in admin from `/api/me/` (subset of the backend `MeUser`).
public struct MeUser: Decodable, Sendable {
    public let username: String
    public let email: String
    public let firstName: String
    public let lastName: String
    public let accountType: String
    public let isStaff: Bool
    public let isSuperuser: Bool
    public let allTenantAccess: Bool
    public let effectiveScopes: [String]
    public let tenantNames: [String]

    private enum K: String, CodingKey {
        case username, email, tenants
        case firstName = "first_name"
        case lastName = "last_name"
        case accountType = "account_type"
        case isStaff = "is_staff"
        case isSuperuser = "is_superuser"
        case allTenantAccess = "all_tenant_access"
        case effectiveScopes = "effective_scopes"
    }
    private struct TenantStub: Decodable { let name: String? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        accountType = try c.decodeIfPresent(String.self, forKey: .accountType) ?? ""
        isStaff = try c.decodeIfPresent(Bool.self, forKey: .isStaff) ?? false
        isSuperuser = try c.decodeIfPresent(Bool.self, forKey: .isSuperuser) ?? false
        allTenantAccess = try c.decodeIfPresent(Bool.self, forKey: .allTenantAccess) ?? false
        effectiveScopes = try c.decodeIfPresent([String].self, forKey: .effectiveScopes) ?? []
        let tenants = try c.decodeIfPresent([TenantStub].self, forKey: .tenants) ?? []
        tenantNames = tenants.compactMap { $0.name }
    }

    public var displayName: String {
        let full = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? username : full
    }
}
