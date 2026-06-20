import Foundation

/// A lightweight eSIM summary — what search results and the customer's eSIM
/// list need (the full backend `EsimInfo` is much larger; this is the subset
/// the native screens display).
public struct EsimSummary: Decodable, Identifiable, Sendable {
    public let iccid: String
    public let coverageName: String?
    public let customer: Customer?
    public var id: String { iccid }

    private enum K: String, CodingKey { case iccid, coverage, customer }
    private struct Coverage: Decodable { let name: String? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        iccid = try c.decodeIfPresent(String.self, forKey: .iccid) ?? ""
        coverageName = (try? c.decodeIfPresent(Coverage.self, forKey: .coverage))?.name
        customer = try c.decodeIfPresent(Customer.self, forKey: .customer)
    }
}

/// `GET /api/esim/{iccid}?search=true` → `{ esim, tenant }`.
public struct EsimSearchResponse: Decodable, Sendable {
    public let esim: EsimSummary?
    public let tenant: String?
}

/// `GET /api/customers/{tenant}/{customer_id}` → `{ customer, tenant }`.
public struct SingleCustomerResponse: Decodable, Sendable {
    public let customer: Customer?
    public let tenant: String?
}

/// `GET /api/esims/{tenant}/?customer__customer_id=…` — paginated, grouped by
/// tenant; flattens `results[].esims`.
public struct AssignedEsimsPage: Decodable, Sendable {
    public let esims: [EsimSummary]

    private enum K: String, CodingKey { case results }
    private struct Group: Decodable { let esims: [EsimSummary]? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let groups = try c.decodeIfPresent([Group].self, forKey: .results) ?? []
        esims = groups.flatMap { $0.esims ?? [] }
    }
}
