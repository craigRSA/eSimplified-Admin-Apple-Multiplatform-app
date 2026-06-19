# eSim Pulse — Phase 1 (MVP) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS desktop window that shows today's consolidated eSimplified revenue and the delta vs yesterday, authenticating to the existing `/api/v1/statistics/` endpoint with a stored Bearer token.

**Architecture:** All non-UI logic lives in a local Swift package, `EsimplifiedKit`, that is fully unit-testable from the command line via `swift test` (true TDD, no Xcode GUI needed). A thin SwiftUI macOS app target (`Esimplified.xcodeproj`) imports the package and renders the window. The package exposes three units behind protocols — credential storage, the statistics HTTP client, and an observable view model — each tested in isolation with in-memory fakes.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (for window level), XCTest, Foundation `URLSession`/`Codable`/`Decimal`, macOS Keychain Services. No third-party dependencies.

## Global Constraints

- Platform floor: **macOS 14.0** (required for the `@Observable` macro).
- Swift tools version: **5.9+**.
- Money values: always `Decimal`, never `Double`/`Float` for storage or comparison. (`Double` is allowed only as a transient step inside the JSON decoder.)
- No third-party dependencies — Foundation/SwiftUI/AppKit/XCTest only.
- API response decimal fields may arrive as **JSON strings** (Django DRF default) **or** numbers — the decoder must accept both.
- The endpoint already excludes the `esimplified` schema and filters `payment_status='success'`; the client adds no filtering of its own.
- Commit after every task with a `feat:`/`test:`/`chore:` prefixed message.

---

## File Structure

```
~/xcode/eSimPulse/
├── EsimplifiedKit/                      # local Swift package (testable core)
│   ├── Package.swift
│   ├── Sources/EsimplifiedKit/
│   │   ├── Credentials.swift          # Credentials struct + CredentialStore protocol + InMemoryCredentialStore
│   │   ├── KeychainCredentialStore.swift
│   │   ├── DashboardStats.swift       # DashboardStats model + JSON decoding (+ FlexibleDecimal)
│   │   ├── StatisticsClient.swift     # StatisticsClient protocol + LiveStatisticsClient + StatsError + DateRange
│   │   └── DashboardViewModel.swift   # @Observable view model + DashboardState
│   └── Tests/EsimplifiedKitTests/
│       ├── Fixtures/statistics_response.json
│       ├── CredentialStoreTests.swift
│       ├── DashboardStatsTests.swift
│       ├── StatisticsClientTests.swift
│       ├── MockURLProtocol.swift
│       └── DashboardViewModelTests.swift
└── eSimPulse/                         # Xcode macOS app target (UI shell)
    ├── eSimPulseApp.swift
    ├── DashboardView.swift
    ├── SettingsView.swift
    └── FloatingWindow.swift
```

---

### Task 1: Package scaffold + credential storage

**Files:**
- Create: `~/xcode/eSimPulse/EsimplifiedKit/Package.swift`
- Create: `~/xcode/eSimPulse/EsimplifiedKit/Sources/EsimplifiedKit/Credentials.swift`
- Create: `~/xcode/eSimPulse/EsimplifiedKit/Sources/EsimplifiedKit/KeychainCredentialStore.swift`
- Test: `~/xcode/eSimPulse/EsimplifiedKit/Tests/EsimplifiedKitTests/CredentialStoreTests.swift`

**Interfaces:**
- Produces:
  - `struct Credentials: Equatable { let host: String; let token: String }`
  - `protocol CredentialStore { func save(_ credentials: Credentials) throws; func load() throws -> Credentials?; func clear() throws }`
  - `final class InMemoryCredentialStore: CredentialStore` (test/preview fake)
  - `final class KeychainCredentialStore: CredentialStore` (real, used by the app)

- [ ] **Step 1: Create the package manifest**

Create `~/xcode/eSimPulse/EsimplifiedKit/Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EsimplifiedKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EsimplifiedKit", targets: ["EsimplifiedKit"]),
    ],
    targets: [
        .target(name: "EsimplifiedKit"),
        .testTarget(name: "EsimplifiedKitTests", dependencies: ["EsimplifiedKit"]),
    ]
)
```

- [ ] **Step 2: Write the failing test**

Create `Tests/EsimplifiedKitTests/CredentialStoreTests.swift`:

```swift
import XCTest
@testable import EsimplifiedKit

final class CredentialStoreTests: XCTestCase {
    func test_inMemory_save_then_load_returns_same_credentials() throws {
        let store = InMemoryCredentialStore()
        let creds = Credentials(host: "https://admin.example.com", token: "abc123")

        try store.save(creds)

        XCTAssertEqual(try store.load(), creds)
    }

    func test_inMemory_load_when_empty_returns_nil() throws {
        let store = InMemoryCredentialStore()
        XCTAssertNil(try store.load())
    }

    func test_inMemory_clear_removes_credentials() throws {
        let store = InMemoryCredentialStore()
        try store.save(Credentials(host: "h", token: "t"))

        try store.clear()

        XCTAssertNil(try store.load())
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd ~/xcode/eSimPulse/EsimplifiedKit && swift test --filter CredentialStoreTests`
Expected: FAIL — `cannot find 'InMemoryCredentialStore' in scope` (compile error).

- [ ] **Step 4: Implement Credentials + protocol + in-memory fake**

Create `Sources/EsimplifiedKit/Credentials.swift`:

```swift
import Foundation

public struct Credentials: Equatable, Sendable {
    public let host: String
    public let token: String

    public init(host: String, token: String) {
        self.host = host
        self.token = token
    }
}

public protocol CredentialStore {
    func save(_ credentials: Credentials) throws
    func load() throws -> Credentials?
    func clear() throws
}

public final class InMemoryCredentialStore: CredentialStore {
    private var stored: Credentials?

    public init() {}

    public func save(_ credentials: Credentials) throws { stored = credentials }
    public func load() throws -> Credentials? { stored }
    public func clear() throws { stored = nil }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd ~/xcode/eSimPulse/EsimplifiedKit && swift test --filter CredentialStoreTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Implement the real Keychain store**

Create `Sources/EsimplifiedKit/KeychainCredentialStore.swift`. The host is stored as the Keychain account; the token is the secret. A fixed service name namespaces the item.

```swift
import Foundation
import Security

public final class KeychainCredentialStore: CredentialStore {
    private let service = "io.esimplified.esimpulse"
    private let account = "bearer"

    public init() {}

    public func save(_ credentials: Credentials) throws {
        try clear()
        let payload = "\(credentials.host)\n\(credentials.token)"
        let data = Data(payload.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    public func load() throws -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let payload = String(data: data, encoding: .utf8) else {
            throw KeychainError.unhandled(status)
        }
        let parts = payload.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return Credentials(host: String(parts[0]), token: String(parts[1]))
    }

    public func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}

public enum KeychainError: Error, Equatable {
    case unhandled(OSStatus)
}
```

> Note: `KeychainCredentialStore` is intentionally **not** unit-tested here — Keychain access from a non-bundled `swift test` binary can prompt or behave differently than inside the signed app. It is verified manually in Task 5. The `InMemoryCredentialStore` is what the unit tests and SwiftUI previews use.

- [ ] **Step 7: Run the full package build to confirm both stores compile**

Run: `cd ~/xcode/eSimPulse/EsimplifiedKit && swift build`
Expected: `Build complete!`

- [ ] **Step 8: Commit**

```bash
cd ~/xcode/eSimPulse && git add EsimplifiedKit && \
  git commit -m "feat: EsimplifiedKit package scaffold + credential storage"
```

---

### Task 2: DashboardStats model + JSON decoding

**Files:**
- Create: `~/xcode/eSimPulse/EsimplifiedKit/Sources/EsimplifiedKit/DashboardStats.swift`
- Create: `~/xcode/eSimPulse/EsimplifiedKit/Tests/EsimplifiedKitTests/Fixtures/statistics_response.json`
- Test: `~/xcode/eSimPulse/EsimplifiedKit/Tests/EsimplifiedKitTests/DashboardStatsTests.swift`

**Interfaces:**
- Produces:
  - `struct DayRevenue: Decodable, Equatable { let date: String; let revenue: Decimal }`
  - `struct DashboardStats: Decodable, Equatable { let revenueToday: Decimal; let revenueYesterday: Decimal; let revenuePerDate: [DayRevenue]; let successOrders: Int }`
  - `static func DashboardStats.decode(from data: Data) throws -> DashboardStats`

- [ ] **Step 1: Add the fixture (real-shaped response, decimals as strings)**

Create `Tests/EsimplifiedKitTests/Fixtures/statistics_response.json`:

```json
{
  "tenants": 5,
  "success_orders": 1234,
  "revenue": "100000.00",
  "revenue_today": "1523.45",
  "revenue_yesterday": "1402.10",
  "current": {
    "success_orders": 87,
    "revenue": "9000.00",
    "revenue_per_date": [
      { "date": "2026-06-11", "revenue": "1100.00" },
      { "date": "2026-06-12", "revenue": "1250.50" },
      { "date": "2026-06-13", "revenue": "1523.45" }
    ]
  }
}
```

Register the fixtures folder as a resource by changing the test target in
`Package.swift` to:

```swift
.testTarget(
    name: "EsimplifiedKitTests",
    dependencies: ["EsimplifiedKit"],
    resources: [.copy("Fixtures")]
),
```

- [ ] **Step 2: Write the failing test**

Create `Tests/EsimplifiedKitTests/DashboardStatsTests.swift`:

```swift
import XCTest
@testable import EsimplifiedKit

final class DashboardStatsTests: XCTestCase {
    private func fixtureData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "statistics_response",
                                                  withExtension: "json",
                                                  subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func test_decode_parses_string_decimals_from_real_response() throws {
        let stats = try DashboardStats.decode(from: try fixtureData())

        XCTAssertEqual(stats.revenueToday, Decimal(string: "1523.45"))
        XCTAssertEqual(stats.revenueYesterday, Decimal(string: "1402.10"))
        XCTAssertEqual(stats.successOrders, 87)
        XCTAssertEqual(stats.revenuePerDate.count, 3)
        XCTAssertEqual(stats.revenuePerDate.last,
                       DayRevenue(date: "2026-06-13", revenue: Decimal(string: "1523.45")!))
    }

    func test_decode_accepts_numeric_decimals() throws {
        let json = """
        { "revenue_today": 10.5, "revenue_yesterday": 9,
          "current": { "success_orders": 3, "revenue_per_date": [] } }
        """
        let stats = try DashboardStats.decode(from: Data(json.utf8))

        XCTAssertEqual(stats.revenueToday, Decimal(string: "10.5"))
        XCTAssertEqual(stats.revenueYesterday, Decimal(string: "9"))
        XCTAssertEqual(stats.successOrders, 3)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd ~/xcode/eSimPulse/EsimplifiedKit && swift test --filter DashboardStatsTests`
Expected: FAIL — `cannot find 'DashboardStats' in scope`.

- [ ] **Step 4: Implement the model + tolerant decimal decoding**

Create `Sources/EsimplifiedKit/DashboardStats.swift`:

```swift
import Foundation

/// Decodes a Decimal that may arrive as a JSON string (DRF default) or a JSON number.
struct FlexibleDecimal: Decodable {
    let value: Decimal
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self), let dec = Decimal(string: string) {
            value = dec
        } else {
            value = try container.decode(Decimal.self)
        }
    }
}

public struct DayRevenue: Decodable, Equatable, Sendable {
    public let date: String
    public let revenue: Decimal

    public init(date: String, revenue: Decimal) {
        self.date = date
        self.revenue = revenue
    }

    private enum CodingKeys: String, CodingKey { case date, revenue }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        revenue = try c.decode(FlexibleDecimal.self, forKey: .revenue).value
    }
}

public struct DashboardStats: Decodable, Equatable, Sendable {
    public let revenueToday: Decimal
    public let revenueYesterday: Decimal
    public let revenuePerDate: [DayRevenue]
    public let successOrders: Int

    private enum CodingKeys: String, CodingKey {
        case revenueToday = "revenue_today"
        case revenueYesterday = "revenue_yesterday"
        case current
    }

    private enum CurrentKeys: String, CodingKey {
        case successOrders = "success_orders"
        case revenuePerDate = "revenue_per_date"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        revenueToday = try c.decode(FlexibleDecimal.self, forKey: .revenueToday).value
        revenueYesterday = try c.decode(FlexibleDecimal.self, forKey: .revenueYesterday).value

        let current = try c.nestedContainer(keyedBy: CurrentKeys.self, forKey: .current)
        successOrders = try current.decode(Int.self, forKey: .successOrders)
        revenuePerDate = try current.decodeIfPresent([DayRevenue].self, forKey: .revenuePerDate) ?? []
    }

    public static func decode(from data: Data) throws -> DashboardStats {
        try JSONDecoder().decode(DashboardStats.self, from: data)
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd ~/xcode/eSimPulse/EsimplifiedKit && swift test --filter DashboardStatsTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
cd ~/xcode/eSimPulse && git add EsimplifiedKit && \
  git commit -m "feat: DashboardStats model with tolerant decimal decoding"
```

---

### Task 3: StatisticsClient (HTTP + error mapping)

**Files:**
- Create: `~/xcode/eSimPulse/EsimplifiedKit/Sources/EsimplifiedKit/StatisticsClient.swift`
- Create: `~/xcode/eSimPulse/EsimplifiedKit/Tests/EsimplifiedKitTests/MockURLProtocol.swift`
- Test: `~/xcode/eSimPulse/EsimplifiedKit/Tests/EsimplifiedKitTests/StatisticsClientTests.swift`

**Interfaces:**
- Consumes: `DashboardStats.decode(from:)` (Task 2), `Credentials` (Task 1).
- Produces:
  - `enum DateRange: String { case today = "today"; case last7Days = "last_7_days" }`
  - `enum StatsError: Error, Equatable { case authExpired; case unreachable; case noData }`
  - `protocol StatisticsClient { func fetch(dateRange: DateRange) async throws -> DashboardStats }`
  - `final class LiveStatisticsClient: StatisticsClient` with `init(credentials: Credentials, session: URLSession = .shared)`

- [ ] **Step 1: Add the URLProtocol mock test helper**

Create `Tests/EsimplifiedKitTests/MockURLProtocol.swift`:

```swift
import Foundation

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/EsimplifiedKitTests/StatisticsClientTests.swift`:

```swift
import XCTest
@testable import EsimplifiedKit

final class StatisticsClientTests: XCTestCase {
    private let creds = Credentials(host: "https://admin.example.com", token: "tok-123")

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeClient() -> LiveStatisticsClient {
        LiveStatisticsClient(credentials: creds, session: MockURLProtocol.makeSession())
    }

    func test_fetch_builds_correct_url_and_auth_header() async throws {
        var captured: URLRequest?
        MockURLProtocol.handler = { request in
            captured = request
            let body = #"{"revenue_today":"1.00","revenue_yesterday":"1.00","current":{"success_orders":0,"revenue_per_date":[]}}"#
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(body.utf8))
        }

        _ = try await makeClient().fetch(dateRange: .last7Days)

        XCTAssertEqual(captured?.url?.absoluteString,
                       "https://admin.example.com/api/v1/statistics/?date_range=last_7_days")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer tok-123")
    }

    func test_fetch_returns_decoded_stats_on_200() async throws {
        MockURLProtocol.handler = { request in
            let body = #"{"revenue_today":"1523.45","revenue_yesterday":"1402.10","current":{"success_orders":87,"revenue_per_date":[]}}"#
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(body.utf8))
        }

        let stats = try await makeClient().fetch(dateRange: .last7Days)

        XCTAssertEqual(stats.revenueToday, Decimal(string: "1523.45"))
    }

    func test_fetch_maps_401_to_authExpired() async {
        MockURLProtocol.handler = { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }

        await assertThrows(.authExpired) { try await self.makeClient().fetch(dateRange: .today) }
    }

    func test_fetch_maps_malformed_body_to_noData() async {
        MockURLProtocol.handler = { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("not json".utf8))
        }

        await assertThrows(.noData) { try await self.makeClient().fetch(dateRange: .today) }
    }

    func test_fetch_maps_transport_failure_to_unreachable() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        await assertThrows(.unreachable) { try await self.makeClient().fetch(dateRange: .today) }
    }

    private func assertThrows(_ expected: StatsError,
                              _ block: () async throws -> Void,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await block()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as StatsError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd ~/xcode/eSimPulse/EsimplifiedKit && swift test --filter StatisticsClientTests`
Expected: FAIL — `cannot find 'LiveStatisticsClient' in scope`.

- [ ] **Step 4: Implement the client**

Create `Sources/EsimplifiedKit/StatisticsClient.swift`:

```swift
import Foundation

public enum DateRange: String, Sendable {
    case today = "today"
    case last7Days = "last_7_days"
}

public enum StatsError: Error, Equatable, Sendable {
    case authExpired
    case unreachable
    case noData
}

public protocol StatisticsClient: Sendable {
    func fetch(dateRange: DateRange) async throws -> DashboardStats
}

public final class LiveStatisticsClient: StatisticsClient {
    private let credentials: Credentials
    private let session: URLSession

    public init(credentials: Credentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    public func fetch(dateRange: DateRange) async throws -> DashboardStats {
        guard var components = URLComponents(string: credentials.host) else {
            throw StatsError.unreachable
        }
        components.path = "/api/v1/statistics/"
        components.queryItems = [URLQueryItem(name: "date_range", value: dateRange.rawValue)]
        guard let url = components.url else { throw StatsError.unreachable }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw StatsError.unreachable
        }

        guard let http = response as? HTTPURLResponse else { throw StatsError.unreachable }
        switch http.statusCode {
        case 200:
            do {
                return try DashboardStats.decode(from: data)
            } catch {
                throw StatsError.noData
            }
        case 401, 403:
            throw StatsError.authExpired
        default:
            throw StatsError.unreachable
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd ~/xcode/eSimPulse/EsimplifiedKit && swift test --filter StatisticsClientTests`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
cd ~/xcode/eSimPulse && git add EsimplifiedKit && \
  git commit -m "feat: LiveStatisticsClient with URL building and error mapping"
```

---

### Task 4: DashboardViewModel (state machine)

**Files:**
- Create: `~/xcode/eSimPulse/EsimplifiedKit/Sources/EsimplifiedKit/DashboardViewModel.swift`
- Test: `~/xcode/eSimPulse/EsimplifiedKit/Tests/EsimplifiedKitTests/DashboardViewModelTests.swift`

**Interfaces:**
- Consumes: `StatisticsClient` (Task 3), `DashboardStats` (Task 2), `StatsError` (Task 3).
- Produces:
  - `enum DashboardState: Equatable { case loading; case loaded(DashboardStats, stale: Bool); case error(StatsError) }`
  - `@Observable @MainActor final class DashboardViewModel` with `var state: DashboardState`, `init(client: StatisticsClient)`, `func refresh() async`, and a computed `var deltaPercent: Decimal?` (today vs yesterday; nil when yesterday == 0).

- [ ] **Step 1: Write the failing tests**

Create `Tests/EsimplifiedKitTests/DashboardViewModelTests.swift`:

```swift
import XCTest
@testable import EsimplifiedKit

@MainActor
final class DashboardViewModelTests: XCTestCase {
    private func stats(today: String, yesterday: String) -> DashboardStats {
        let json = """
        {"revenue_today":"\(today)","revenue_yesterday":"\(yesterday)",
         "current":{"success_orders":1,"revenue_per_date":[]}}
        """
        return try! DashboardStats.decode(from: Data(json.utf8))
    }

    func test_refresh_success_sets_loaded_state() async {
        let client = StubClient(result: .success(stats(today: "100", yesterday: "80")))
        let vm = DashboardViewModel(client: client)

        await vm.refresh()

        guard case let .loaded(s, stale) = vm.state else { return XCTFail("not loaded") }
        XCTAssertEqual(s.revenueToday, Decimal(string: "100"))
        XCTAssertFalse(stale)
    }

    func test_refresh_authExpired_sets_error_state() async {
        let client = StubClient(result: .failure(.authExpired))
        let vm = DashboardViewModel(client: client)

        await vm.refresh()

        XCTAssertEqual(vm.state, .error(.authExpired))
    }

    func test_refresh_unreachable_after_loaded_keeps_last_value_as_stale() async {
        let client = StubClient(result: .success(stats(today: "100", yesterday: "80")))
        let vm = DashboardViewModel(client: client)
        await vm.refresh()

        client.result = .failure(.unreachable)
        await vm.refresh()

        guard case let .loaded(s, stale) = vm.state else { return XCTFail("not loaded") }
        XCTAssertEqual(s.revenueToday, Decimal(string: "100"))
        XCTAssertTrue(stale)
    }

    func test_deltaPercent_computes_today_vs_yesterday() async {
        let client = StubClient(result: .success(stats(today: "120", yesterday: "100")))
        let vm = DashboardViewModel(client: client)
        await vm.refresh()

        XCTAssertEqual(vm.deltaPercent, Decimal(string: "20"))
    }

    func test_deltaPercent_is_nil_when_yesterday_is_zero() async {
        let client = StubClient(result: .success(stats(today: "120", yesterday: "0")))
        let vm = DashboardViewModel(client: client)
        await vm.refresh()

        XCTAssertNil(vm.deltaPercent)
    }
}

private final class StubClient: StatisticsClient, @unchecked Sendable {
    var result: Result<DashboardStats, StatsError>
    init(result: Result<DashboardStats, StatsError>) { self.result = result }
    func fetch(dateRange: DateRange) async throws -> DashboardStats {
        try result.get()
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ~/xcode/eSimPulse/EsimplifiedKit && swift test --filter DashboardViewModelTests`
Expected: FAIL — `cannot find 'DashboardViewModel' in scope`.

- [ ] **Step 3: Implement the view model**

Create `Sources/EsimplifiedKit/DashboardViewModel.swift`:

```swift
import Foundation
import Observation

public enum DashboardState: Equatable, Sendable {
    case loading
    case loaded(DashboardStats, stale: Bool)
    case error(StatsError)
}

@Observable
@MainActor
public final class DashboardViewModel {
    public private(set) var state: DashboardState = .loading

    private let client: StatisticsClient

    public init(client: StatisticsClient) {
        self.client = client
    }

    public func refresh() async {
        do {
            let stats = try await client.fetch(dateRange: .last7Days)
            state = .loaded(stats, stale: false)
        } catch let error as StatsError {
            handle(error)
        } catch {
            handle(.unreachable)
        }
    }

    private func handle(_ error: StatsError) {
        // On a transient failure, keep the last good numbers and flag them stale.
        if error == .unreachable, case let .loaded(stats, _) = state {
            state = .loaded(stats, stale: true)
        } else {
            state = .error(error)
        }
    }

    /// Percentage change of today vs yesterday; nil when yesterday is zero.
    public var deltaPercent: Decimal? {
        guard case let .loaded(stats, _) = state, stats.revenueYesterday != 0 else { return nil }
        let diff = stats.revenueToday - stats.revenueYesterday
        return diff / stats.revenueYesterday * 100
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ~/xcode/eSimPulse/EsimplifiedKit && swift test --filter DashboardViewModelTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Run the entire package test suite**

Run: `cd ~/xcode/eSimPulse/EsimplifiedKit && swift test`
Expected: PASS — all tests from Tasks 1–4 (15 total) green.

- [ ] **Step 6: Commit**

```bash
cd ~/xcode/eSimPulse && git add EsimplifiedKit && \
  git commit -m "feat: DashboardViewModel state machine + delta computation"
```

---

### Task 5: macOS app shell (UI window) — manual verification

This task creates the Xcode app target and wires the UI. It is verified by
building and running, not by unit tests (SwiftUI views over an `@Observable`
view model are covered indirectly by Task 4).

**Files:**
- Create: `Esimplified.xcodeproj` (via Xcode — see Step 1)
- Create: `~/xcode/eSimPulse/eSimPulse/eSimPulseApp.swift`
- Create: `~/xcode/eSimPulse/eSimPulse/FloatingWindow.swift`
- Create: `~/xcode/eSimPulse/eSimPulse/DashboardView.swift`
- Create: `~/xcode/eSimPulse/eSimPulse/SettingsView.swift`

**Interfaces:**
- Consumes: `DashboardViewModel`, `DashboardState`, `KeychainCredentialStore`, `Credentials`, `LiveStatisticsClient` from `EsimplifiedKit`.

- [ ] **Step 1: Create the Xcode app target**

In Xcode: **File ▸ New ▸ Project ▸ macOS ▸ App**.
- Product Name: `eSimPulse`
- Interface: SwiftUI, Language: Swift
- Save into `~/xcode/eSimPulse` (so the `.xcodeproj` sits beside `EsimplifiedKit/` and `docs/`).
- Delete the auto-generated `ContentView.swift`.

Then add the local package: **File ▸ Add Package Dependencies ▸ Add Local…** →
select `~/xcode/eSimPulse/EsimplifiedKit`, and add the `EsimplifiedKit` library to
the `eSimPulse` target.

- [ ] **Step 2: App entry point with refresh timer**

Replace the generated `eSimPulseApp.swift` with `~/xcode/eSimPulse/eSimPulse/eSimPulseApp.swift`:

```swift
import SwiftUI
import EsimplifiedKit

@main
struct eSimPulseApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("eSim Pulse", id: "main") {
            RootView(model: model)
                .frame(width: 280, height: 200)
                .background(FloatingWindowConfigurator())
        }
        .windowResizability(.contentSize)
    }
}

@Observable
@MainActor
final class AppModel {
    let store = KeychainCredentialStore()
    var credentials: Credentials?

    init() {
        credentials = try? store.load()
    }

    func makeViewModel() -> DashboardViewModel? {
        guard let credentials else { return nil }
        return DashboardViewModel(client: LiveStatisticsClient(credentials: credentials))
    }

    func save(host: String, token: String) {
        let creds = Credentials(host: host, token: token)
        try? store.save(creds)
        credentials = creds
    }
}
```

- [ ] **Step 3: Always-on-top floating window**

Create `~/xcode/eSimPulse/eSimPulse/FloatingWindow.swift`:

```swift
import SwiftUI
import AppKit

struct FloatingWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.level = .floating
                window.titlebarAppearsTransparent = true
                window.isMovableByWindowBackground = true
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
```

- [ ] **Step 4: Root + dashboard + settings views**

Create `~/xcode/eSimPulse/eSimPulse/DashboardView.swift`:

```swift
import SwiftUI
import EsimplifiedKit

struct RootView: View {
    @Bindable var model: AppModel
    @State private var showSettings = false

    var body: some View {
        Group {
            if model.credentials == nil {
                SettingsView(model: model)
            } else if let vm = model.makeViewModel() {
                DashboardView(viewModel: vm, showSettings: $showSettings)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model)
        }
    }
}

struct DashboardView: View {
    @State var viewModel: DashboardViewModel
    @Binding var showSettings: Bool
    private let symbol = "$"
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Today").font(.headline)
                Spacer()
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless)
            }
            content
            Spacer()
        }
        .padding()
        .task { await viewModel.refresh() }
        .onReceive(timer) { _ in Task { await viewModel.refresh() } }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case let .loaded(stats, stale):
            VStack(spacing: 4) {
                Text("\(symbol)\(stats.revenueToday.formatted(.number.precision(.fractionLength(2))))")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .opacity(stale ? 0.5 : 1)
                deltaView
            }
        case .error(.authExpired):
            Text("Token expired — update in Settings")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
        case .error:
            Text("No data").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var deltaView: some View {
        if let delta = viewModel.deltaPercent {
            let up = delta >= 0
            Label("\(delta.formatted(.number.precision(.fractionLength(1))))%",
                  systemImage: up ? "arrow.up" : "arrow.down")
                .foregroundStyle(up ? .green : .red)
                .font(.subheadline)
        }
    }
}
```

Create `~/xcode/eSimPulse/eSimPulse/SettingsView.swift`:

```swift
import SwiftUI
import EsimplifiedKit

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var host: String = ""
    @State private var token: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection").font(.headline)
            TextField("Admin host (https://…)", text: $host)
            SecureField("Bearer token", text: $token)
            HStack {
                Spacer()
                Button("Save") {
                    model.save(host: host.trimmingCharacters(in: .whitespaces),
                               token: token.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                .disabled(host.isEmpty || token.isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            host = model.credentials?.host ?? ""
            token = model.credentials?.token ?? ""
        }
    }
}
```

- [ ] **Step 5: Build the app**

Run: `cd ~/xcode/eSimPulse && xcodebuild -project Esimplified.xcodeproj -scheme eSimPulse -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Manual verification (record results)**

Launch the app from Xcode (⌘R) and confirm each:
1. First launch shows the Settings form (no stored credentials).
2. Enter the real admin host + a valid Bearer token, click Save → window shows today's revenue number and a green/red delta.
3. The window floats above other windows and is draggable by its background.
4. Quit and relaunch → it loads straight to the number (token persisted in Keychain), no re-entry needed.
5. Enter a bad token in Settings → body shows "Token expired — update in Settings."

Write the observed result for each of the 5 checks into the task comment / PR description. Do not claim completion until all 5 are confirmed against the live endpoint.

- [ ] **Step 7: Commit**

```bash
cd ~/xcode/eSimPulse && git add -A && \
  git commit -m "feat: macOS app shell — floating window, dashboard + settings views"
```

---

## Self-Review

- **Spec coverage:** Keychain storage (Task 1) ✓; reuse `/api/v1/statistics/` with Bearer + scope (Task 3) ✓; `revenue_today` headline + `revenue_yesterday` delta (Tasks 2, 4, 5) ✓; tolerant decimal decoding for DRF string decimals (Task 2) ✓; 401→auth-expired / transport→stale / bad-JSON→no-data (Tasks 3, 4, 5) ✓; always-on-top floating window (Task 5) ✓; configurable currency symbol noted as Phase 3 (hardcoded `$` placeholder in Task 5, called out) — acceptable for MVP. `revenue_per_date` is decoded now (Task 2) but the sparkline render is **Phase 2**, per spec phasing. Today's order-count display is **Phase 2**.
- **Placeholder scan:** No TBD/TODO; every code step contains complete code. The only hardcoded value is the `$` symbol, explicitly deferred to Phase 3.
- **Type consistency:** `Credentials`, `CredentialStore`, `DashboardStats`, `DayRevenue`, `StatisticsClient`, `DateRange`, `StatsError`, `DashboardState`, `DashboardViewModel.refresh()/deltaPercent`, `LiveStatisticsClient(credentials:session:)` are used identically across tasks.

## Out of Scope (future plans)

- **Phase 2:** 7-day sparkline (Swift Charts over `revenuePerDate`) + today's order count (second `?date_range=today` fetch).
- **Phase 3:** launch-at-login, configurable refresh interval, configurable currency symbol.
