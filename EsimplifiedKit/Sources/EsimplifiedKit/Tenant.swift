import Foundation

/// A tenant from `/api/tenants/`. `schemaName` is what the API expects in paths
/// (e.g. `/statistics/{schemaName}/`).
public struct Tenant: Decodable, Identifiable, Hashable, Sendable {
    public var id: String { schemaName }
    public let name: String
    public let schemaName: String

    private enum K: String, CodingKey {
        case name
        case schemaName = "schema_name"
    }

    public init(name: String, schemaName: String) {
        self.name = name
        self.schemaName = schemaName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        schemaName = try c.decodeIfPresent(String.self, forKey: .schemaName) ?? ""
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
