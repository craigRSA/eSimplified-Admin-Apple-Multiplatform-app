import AppIntents
import Foundation

/// Shared fetch for the revenue App Intents — reads the signed-in session from
/// the Keychain, refreshes the OAuth token if needed, and fetches stats. Runs in
/// the background (no app launch) so Siri can answer with the app closed.
enum RevenueIntentSupport {
    static func fetch() async throws -> AdminDashboardStats {
        let store = KeychainSessionStore()
        guard var session = try? store.load() else { throw RevenueIntentError.notSignedIn }
        if session.expiresAt <= Date(), let auth = authClient(),
           let refreshed = try? await auth.refresh(host: session.host, refreshToken: session.refreshToken) {
            try? store.save(refreshed)
            session = refreshed
        }
        let client = LiveAPIClient(host: session.host, accessToken: session.accessToken)
        do {
            return try await client.get("/api/statistics/", query: [:], as: AdminDashboardStats.self)
        } catch APIError.authExpired {
            throw RevenueIntentError.notSignedIn
        }
    }

    static func money(_ d: Decimal) -> String {
        d.formatted(.currency(code: "USD"))
    }

    private static func authClient() -> LiveAuthClient? {
        let id = (Bundle.main.object(forInfoDictionaryKey: "ESPClientID") as? String) ?? ""
        let secret = (Bundle.main.object(forInfoDictionaryKey: "ESPClientSecret") as? String) ?? ""
        guard !id.isEmpty, !secret.isEmpty else { return nil }
        return LiveAuthClient(clientID: id, clientSecret: secret)
    }
}

enum RevenueIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notSignedIn
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notSignedIn: "Open eSimplified and sign in first."
        }
    }
}

public struct TodaysRevenueIntent: AppIntent {
    public static let title: LocalizedStringResource = "Today's Revenue"
    public static let description = IntentDescription("eSimplified's consolidated revenue so far today.")
    public static let openAppWhenRun = false
    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let stats = try await RevenueIntentSupport.fetch()
        let amount = RevenueIntentSupport.money(stats.revenueToday)
        return .result(value: amount, dialog: IntentDialog("eSimplified's revenue today is \(amount)."))
    }
}

public struct YesterdayRevenueIntent: AppIntent {
    public static let title: LocalizedStringResource = "Yesterday's Revenue"
    public static let description = IntentDescription("eSimplified's consolidated revenue for yesterday.")
    public static let openAppWhenRun = false
    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let stats = try await RevenueIntentSupport.fetch()
        let amount = RevenueIntentSupport.money(stats.revenueYesterday)
        return .result(value: amount, dialog: IntentDialog("eSimplified's revenue yesterday was \(amount)."))
    }
}

public struct RevenueVsYesterdayIntent: AppIntent {
    public static let title: LocalizedStringResource = "Revenue vs Yesterday"
    public static let description = IntentDescription("How today's eSimplified revenue compares to yesterday.")
    public static let openAppWhenRun = false
    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let stats = try await RevenueIntentSupport.fetch()
        let today = RevenueIntentSupport.money(stats.revenueToday)
        guard let delta = stats.deltaPercent else {
            return .result(dialog: IntentDialog("eSimplified's revenue today is \(today)."))
        }
        let up = delta >= 0
        let pct = abs(delta).formatted(.number.precision(.fractionLength(1)))
        return .result(dialog: IntentDialog(
            "eSimplified's revenue today is \(today), \(up ? "up" : "down") \(pct) percent versus yesterday."))
    }
}

/// Makes the package's App Intents discoverable when included by the app.
public struct EsimplifiedKitPackage: AppIntentsPackage {}
