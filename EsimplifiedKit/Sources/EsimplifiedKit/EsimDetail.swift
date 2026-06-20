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
    public let whitelist: [Whitelist]

    private enum K: String, CodingKey {
        case iccid, imsi, coverage, packages, archived, whitelist
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
        // Every field is tolerant — one type mismatch must not blank the whole
        // panel. (imsi is a JSON number, not a string.)
        iccid = (try? c.decode(String.self, forKey: .iccid)) ?? ""
        esimName = try? c.decode(String.self, forKey: .esimName)
        imsi = (try? c.decode(String.self, forKey: .imsi)) ?? (try? c.decode(Int.self, forKey: .imsi)).map(String.init)
        coverageName = (try? c.decode(Named.self, forKey: .coverage))?.name
        smDpAddress = try? c.decode(String.self, forKey: .smDpAddress)
        matchingId = try? c.decode(String.self, forKey: .matchingId)
        autoTopUp = (try? c.decode(Bool.self, forKey: .autoTopUp)) ?? false
        archived = (try? c.decode(Bool.self, forKey: .archived)) ?? false
        totalDataAllowanceGB = (try? c.decode(FlexibleDecimal.self, forKey: .totalDataAllowanceGB))?.value
        totalDataRemainingGB = (try? c.decode(FlexibleDecimal.self, forKey: .totalDataRemainingGB))?.value
        euicc = try? c.decode(EuiccProfile.self, forKey: .euicc)
        packages = (try? c.decode([EsimPackage].self, forKey: .packages)) ?? []
        openDataSessions = (try? c.decode([OpenDataSession].self, forKey: .openDataSessions)) ?? []
        latestLocation = try? c.decode(EsimLocation.self, forKey: .latestLocation)
        whitelist = (try? c.decode([Whitelist].self, forKey: .whitelist)) ?? []
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
    public let name: String?            // internal template name — NOT for display
    public let status: String?
    public let dataAllowanceGB: Decimal?
    public let dateCreatedEpoch: Double?
    public let supportedCountries: [String]
    public let packageCountryName: String?
    public let timeAllowanceDays: Int?
    public let nestedPackageName: String?   // package.name — used for Unlimited detection
    public var id: String { "\(name ?? "?")-\(dateCreatedEpoch ?? 0)" }

    private enum K: String, CodingKey {
        case name, status, package
        case dataAllowanceGB = "data_allowance_gigabytes"
        case dateCreatedEpoch = "date_created_epoch"
        case supportedCountries = "supported_countries"
        case packageCountryName = "package_country_name"
        case timeAllowanceDays = "time_allowance_days"
    }
    private struct Named: Decodable { let name: String? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        dataAllowanceGB = (try? c.decodeIfPresent(FlexibleDecimal.self, forKey: .dataAllowanceGB))??.value
        dateCreatedEpoch = try c.decodeIfPresent(Double.self, forKey: .dateCreatedEpoch)
        packageCountryName = try? c.decodeIfPresent(String.self, forKey: .packageCountryName)
        timeAllowanceDays = try? c.decodeIfPresent(Int.self, forKey: .timeAllowanceDays)
        nestedPackageName = (try? c.decodeIfPresent(Named.self, forKey: .package))??.name
        // supported_countries may be [String] or [{name}]
        if let names = try? c.decodeIfPresent([String].self, forKey: .supportedCountries) {
            supportedCountries = names
        } else if let objs = try? c.decodeIfPresent([Named].self, forKey: .supportedCountries) {
            supportedCountries = objs.compactMap { $0.name }
        } else {
            supportedCountries = []
        }
    }

    /// The user-facing package label. The API has no display-ready name, so this
    /// is composed exactly like the web's `packageName()`:
    /// `<country> <allowance|Unlimited> <days> Day(s)`.
    public var displayName: String {
        let country = packageCountryName ?? ""
        let days = timeAllowanceDays ?? 0
        let dayUnit = days == 1 ? "Day" : "Days"
        let gb = dataAllowanceGB ?? 0
        let isUnlimited = (nestedPackageName?.contains("Unlimited") ?? false) || gb < 0
        let allowance = isUnlimited ? "Unlimited" : Self.formatDataGB(gb)
        return "\(country) \(allowance) \(days) \(dayUnit)"
            .trimmingCharacters(in: .whitespaces)
    }

    /// Port of the web `format_data_gb`: parseInt truncates toward zero, then
    /// `< 0` → "Unlimited", `< 1` → MB (always "0 MB" once non-negative), else GB.
    static func formatDataGB(_ gb: Decimal) -> String {
        let dataInt = NSDecimalNumber(decimal: gb).intValue   // truncate toward zero, like parseInt
        if dataInt < 0 { return "Unlimited" }
        if dataInt < 1 { return "\(dataInt / 1024) MB" }
        return "\(dataInt) GB"
    }
}

public struct OpenDataSession: Decodable, Sendable {
    public let openedDate: Double?   // epoch
    public let usageKb: Double?

    private enum K: String, CodingKey {
        case openedDate = "opened_date"
        case usageKb = "usage_kb"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        openedDate = try? c.decode(Double.self, forKey: .openedDate)
        usageKb = try? c.decode(Double.self, forKey: .usageKb)
    }
}

public struct EsimLocation: Decodable, Sendable, Identifiable {
    public let countryName: String?
    public let dateEpoch: Double?
    public let `operator`: String?
    public let dataAllowed: Bool
    public var id: String { "\(dateEpoch ?? 0)-\(countryName ?? "")-\(`operator` ?? "")" }

    private enum K: String, CodingKey {
        case `operator`
        case countryName = "country_name"
        case dateEpoch = "date_epoch"
        case dataAllowed = "data_allowed"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        countryName = try c.decodeIfPresent(String.self, forKey: .countryName)
        dateEpoch = try? c.decode(Double.self, forKey: .dateEpoch)
        `operator` = try c.decodeIfPresent(String.self, forKey: .operator)
        dataAllowed = try c.decodeIfPresent(Bool.self, forKey: .dataAllowed) ?? false
    }
}

/// One whitelist entry (on the eSIM object).
public struct Whitelist: Decodable, Sendable, Identifiable {
    public let country: String?
    public let `operator`: String?
    public let whitelistName: String?
    public let dataAllowed: Bool
    public let bestConnectivity: String?
    public var id: String { "\(country ?? "")-\(`operator` ?? "")-\(whitelistName ?? "")" }

    private enum K: String, CodingKey {
        case country, `operator`
        case whitelistName = "whitelist_name"
        case dataAllowed = "data_allowed"
        case bestConnectivity = "best_connectivity"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        country = try? c.decode(String.self, forKey: .country)
        `operator` = try? c.decode(String.self, forKey: .operator)
        whitelistName = try? c.decode(String.self, forKey: .whitelistName)
        dataAllowed = (try? c.decode(Bool.self, forKey: .dataAllowed)) ?? false
        bestConnectivity = try? c.decode(String.self, forKey: .bestConnectivity)
    }
}

/// One session / CDR record from `GET /api/esim/{iccid}/cdr/`.
public struct EsimSession: Decodable, Sendable, Identifiable {
    public let type: String?
    public let countryName: String?
    public let connectTimeEpoch: Double?
    public let closeTimeEpoch: Double?
    public let durationBytes: Double?    // raw bytes ("duration") — the displayed usage
    public let durationGb: Double?       // present in the API but NOT used for the usage cell
    public var id: String { "\(connectTimeEpoch ?? 0)-\(type ?? "")" }

    private enum K: String, CodingKey {
        case type
        case countryName = "country_name"
        case connectTimeEpoch = "connect_time_epoch"
        case closeTimeEpoch = "close_time_epoch"
        case durationBytes = "duration"
        case durationGb = "duration_gb"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        type = try? c.decode(String.self, forKey: .type)
        countryName = try? c.decode(String.self, forKey: .countryName)
        connectTimeEpoch = try? c.decode(Double.self, forKey: .connectTimeEpoch)
        closeTimeEpoch = try? c.decode(Double.self, forKey: .closeTimeEpoch)
        durationBytes = try? c.decode(Double.self, forKey: .durationBytes)
        durationGb = try? c.decode(Double.self, forKey: .durationGb)
    }
}

/// `GET /api/esim/{iccid}/location/` — paginated location history.
public struct EsimLocationList: Decodable, Sendable {
    public let results: [EsimLocation]
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        results = (try? c.decode([EsimLocation].self, forKey: .results)) ?? []
    }
    private enum CodingKeys: String, CodingKey { case results }
}

/// `GET /api/esim/{iccid}/cdr/` — paginated session/CDR history.
public struct EsimSessionList: Decodable, Sendable {
    public let results: [EsimSession]
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        results = (try? c.decode([EsimSession].self, forKey: .results)) ?? []
    }
    private enum CodingKeys: String, CodingKey { case results }
}

/// `GET /api/esim/{iccid}/` → `{ esim, tenant }` (full detail, no `?search`).
public struct EsimDetailResponse: Decodable, Sendable {
    public let esim: EsimDetail?
    public let tenant: String?
}
