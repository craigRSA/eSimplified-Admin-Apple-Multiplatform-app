import Foundation

public struct IMSIEntry: Decodable, Identifiable, Equatable, Sendable {
    public var id: String { imsi }
    public let imsi: String
    public let unassignedCount: Int
    public let pendingCount: Int
    public let assignedCount: Int

    private enum K: String, CodingKey {
        case imsi
        case unassignedCount = "unassigned_count"
        case pendingCount = "pending_count"
        case assignedCount = "assigned_count"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        imsi = try c.decodeIfPresent(String.self, forKey: .imsi) ?? ""
        unassignedCount = try c.decodeIfPresent(Int.self, forKey: .unassignedCount) ?? 0
        pendingCount = try c.decodeIfPresent(Int.self, forKey: .pendingCount) ?? 0
        assignedCount = try c.decodeIfPresent(Int.self, forKey: .assignedCount) ?? 0
    }
}

/// `/api/inventory/` — eSIM stock totals plus per-IMSI breakdown.
public struct Inventory: Decodable, Sendable {
    public let totalEsims: Int
    public let totalUnassigned: Int
    public let totalPending: Int
    public let totalAssigned: Int
    public let imsis: [IMSIEntry]

    private enum K: String, CodingKey {
        case imsis
        case totalEsims = "total_esims"
        case totalUnassigned = "total_unassigned_esims"
        case totalPending = "total_pending_esims"
        case totalAssigned = "total_assigned_esims"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        totalEsims = try c.decodeIfPresent(Int.self, forKey: .totalEsims) ?? 0
        totalUnassigned = try c.decodeIfPresent(Int.self, forKey: .totalUnassigned) ?? 0
        totalPending = try c.decodeIfPresent(Int.self, forKey: .totalPending) ?? 0
        totalAssigned = try c.decodeIfPresent(Int.self, forKey: .totalAssigned) ?? 0
        imsis = try c.decodeIfPresent([IMSIEntry].self, forKey: .imsis) ?? []
    }
}
