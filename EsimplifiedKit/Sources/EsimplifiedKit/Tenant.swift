import Foundation

/// A tenant from `/api/tenants/`. `schemaName` is what the API expects in paths
/// (e.g. `/statistics/{schemaName}/`); `logoSmall` is the brand mark for the row.
public struct Tenant: Decodable, Identifiable, Hashable, Sendable {
    public var id: String { schemaName }
    public let name: String
    public let schemaName: String
    /// Small brand logo (`settings.logo_small`) when the tenant has one on file.
    public let logoSmall: URL?

    private enum K: String, CodingKey {
        case name
        case schemaName = "schema_name"
        case settings
    }

    /// Just the one field we need out of the tenant's large `settings` object.
    private struct SettingsDTO: Decodable {
        let logoSmall: String?
        private enum K: String, CodingKey { case logoSmall = "logo_small" }
        init(from decoder: Decoder) throws {
            logoSmall = try decoder.container(keyedBy: K.self).decodeIfPresent(String.self, forKey: .logoSmall)
        }
    }

    public init(name: String, schemaName: String, logoSmall: URL? = nil) {
        self.name = name
        self.schemaName = schemaName
        self.logoSmall = logoSmall
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        schemaName = try c.decodeIfPresent(String.self, forKey: .schemaName) ?? ""
        let settings = try? c.decodeIfPresent(SettingsDTO.self, forKey: .settings)
        let raw = (settings ?? nil)?.logoSmall
        logoSmall = raw.flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }
}

/// `/api/tenants/` is a flat paginated list.
public struct TenantsPage: Decodable, Sendable {
    public let tenants: [Tenant]

    private enum K: String, CodingKey { case results }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        tenants = (try c.decodeIfPresent([Tenant].self, forKey: .results) ?? [])
            .filter { !$0.schemaName.isEmpty }
    }
}
