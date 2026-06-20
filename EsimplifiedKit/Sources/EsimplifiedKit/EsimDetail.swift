import Foundation

/// Full eSIM detail from `GET /api/esim/{iccid}/` — the data the web's
/// customer_details page shows in its eSIM panel.
public struct EsimDetail: Decodable, Sendable {
    public let iccid: String
    public let esimName: String?
    public let imsi: String?
    public let coverageName: String?
    public let smDpAddress: String?
    public let matchingId: String?
    public let autoTopUp: Bool
    public let archived: Bool
    public let totalDataAllowanceGB: Decimal?
    public let totalDataRemainingGB: Decimal?
    public let euicc: EuiccProfile?
    public let packages: [EsimPackage]
    public let openDataSessions: [OpenDataSession]
    public let latestLocation: EsimLocation?

    private enum K: String, CodingKey {
        case iccid, imsi, coverage, packages, archived
        case esimName = "esim_name"
        case smDpAddress = "sm_dp_address"
        case matchingId = "matching_id"
        case autoTopUp = "auto_top_up"
        case totalDataAllowanceGB = "total_data_allowance_gigabytes"
        case totalDataRemainingGB = "total_data_usage_remaining_gigabytes"
        case euicc = "euicc_profiles"
        case openDataSessions = "open_data_sessions"
        case latestLocation = "latest_location_update"
    }
    private struct Named: Decodable { let name: String? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        iccid = try c.decodeIfPresent(String.self, forKey: .iccid) ?? ""
        esimName = try c.decodeIfPresent(String.self, forKey: .esimName)
        imsi = try c.decodeIfPresent(String.self, forKey: .imsi)
        coverageName = (try? c.decodeIfPresent(Named.self, forKey: .coverage))?.name
        smDpAddress = try c.decodeIfPresent(String.self, forKey: .smDpAddress)
        matchingId = try c.decodeIfPresent(String.self, forKey: .matchingId)
        autoTopUp = try c.decodeIfPresent(Bool.self, forKey: .autoTopUp) ?? false
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        totalDataAllowanceGB = (try? c.decodeIfPresent(FlexibleDecimal.self, forKey: .totalDataAllowanceGB))??.value
        totalDataRemainingGB = (try? c.decodeIfPresent(FlexibleDecimal.self, forKey: .totalDataRemainingGB))??.value
        euicc = (try? c.decodeIfPresent(EuiccProfile.self, forKey: .euicc)) ?? nil
        packages = ((try? c.decodeIfPresent([EsimPackage].self, forKey: .packages)) ?? nil) ?? []
        openDataSessions = ((try? c.decodeIfPresent([OpenDataSession].self, forKey: .openDataSessions)) ?? nil) ?? []
        latestLocation = (try? c.decodeIfPresent(EsimLocation.self, forKey: .latestLocation)) ?? nil
    }

    /// The newest ACTIVE package, if any.
    public var activePackage: EsimPackage? {
        packages.filter { ($0.status ?? "").uppercased() == "ACTIVE" }
            .max { ($0.dateCreatedEpoch ?? 0) < ($1.dateCreatedEpoch ?? 0) }
    }
}

public struct EuiccProfile: Decodable, Sendable {
    public let state: String?
    public let stateMessage: String?
    public let eid: String?
    public let activationCode: String?
    public let lastOperationDate: Double?
    public let reuseRemainingCount: Int?
    public let maxReuseCount: Int?

    private enum K: String, CodingKey {
        case state, eid
        case stateMessage = "state_message"
        case activationCode = "activation_code"
        case lastOperationDate = "last_operation_date"
        case reuseRemainingCount = "reuse_remaining_count"
        case reusePolicy = "profile_reuse_policy"
    }
    private enum PolicyK: String, CodingKey { case maxCount = "max_count" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        state = try c.decodeIfPresent(String.self, forKey: .state)
        stateMessage = try c.decodeIfPresent(String.self, forKey: .stateMessage)
        eid = try c.decodeIfPresent(String.self, forKey: .eid)
        activationCode = try c.decodeIfPresent(String.self, forKey: .activationCode)
        lastOperationDate = try c.decodeIfPresent(Double.self, forKey: .lastOperationDate)
        reuseRemainingCount = try c.decodeIfPresent(Int.self, forKey: .reuseRemainingCount)
        if let p = try? c.nestedContainer(keyedBy: PolicyK.self, forKey: .reusePolicy) {
            maxReuseCount = try p.decodeIfPresent(Int.self, forKey: .maxCount)
        } else { maxReuseCount = nil }
    }
}

public struct EsimPackage: Decodable, Sendable, Identifiable {
    public let name: String?
    public let status: String?
    public let dataAllowanceGB: Decimal?
    public let dateCreatedEpoch: Double?
    public let supportedCountries: [String]
    public var id: String { "\(name ?? "?")-\(dateCreatedEpoch ?? 0)" }

    private enum K: String, CodingKey {
        case name, status
        case dataAllowanceGB = "data_allowance_gigabytes"
        case dateCreatedEpoch = "date_created_epoch"
        case supportedCountries = "supported_countries"
    }
    private struct Named: Decodable { let name: String? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        dataAllowanceGB = (try? c.decodeIfPresent(FlexibleDecimal.self, forKey: .dataAllowanceGB))??.value
        dateCreatedEpoch = try c.decodeIfPresent(Double.self, forKey: .dateCreatedEpoch)
        // supported_countries may be [String] or [{name}]
        if let names = try? c.decodeIfPresent([String].self, forKey: .supportedCountries) {
            supportedCountries = names
        } else if let objs = try? c.decodeIfPresent([Named].self, forKey: .supportedCountries) {
            supportedCountries = objs.compactMap { $0.name }
        } else {
            supportedCountries = []
        }
    }
}

public struct OpenDataSession: Decodable, Sendable {
    public let coverageName: String?
    public let openedDate: String?
    public let usageKb: Double?

    private enum K: String, CodingKey {
        case coverage
        case openedDate = "opened_date"
        case usageKb = "usage_kb"
    }
    private struct Named: Decodable { let name: String? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        coverageName = (try? c.decodeIfPresent(Named.self, forKey: .coverage))?.name
        openedDate = try c.decodeIfPresent(String.self, forKey: .openedDate)
        usageKb = try c.decodeIfPresent(Double.self, forKey: .usageKb)
    }
}

public struct EsimLocation: Decodable, Sendable {
    public let countryName: String?
    public let dateEpoch: Double?
    public let `operator`: String?
    public let dataAllowed: Bool

    private enum K: String, CodingKey {
        case `operator`
        case countryName = "country_name"
        case dateEpoch = "date_epoch"
        case dataAllowed = "data_allowed"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        countryName = try c.decodeIfPresent(String.self, forKey: .countryName)
        dateEpoch = try c.decodeIfPresent(Double.self, forKey: .dateEpoch)
        `operator` = try c.decodeIfPresent(String.self, forKey: .operator)
        dataAllowed = try c.decodeIfPresent(Bool.self, forKey: .dataAllowed) ?? false
    }
}

/// `GET /api/esim/{iccid}/` → `{ esim, tenant }` (full detail, no `?search`).
public struct EsimDetailResponse: Decodable, Sendable {
    public let esim: EsimDetail?
    public let tenant: String?
}
