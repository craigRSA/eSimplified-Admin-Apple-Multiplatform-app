import AppIntents
import Foundation
import EsimplifiedKit

// App Intents live in the app target (not the Swift package) so Xcode's
// "Extract App Intents Metadata" build step reliably discovers them and Siri /
// Spotlight / Shortcuts can run them.

/// Shared fetch for the revenue intents — reads the signed-in session from the
/// Keychain, refreshes the OAuth token if needed, and fetches stats. Runs in the
/// background so Siri can answer with the app closed.
enum RevenueIntentSupport {
    static func fetch() async throws -> AdminDashboardStats {
        let store = KeychainSessionStore()
        guard let session = try? store.load() else { throw RevenueIntentError.notSignedIn }
        guard let auth = authClient() else { throw RevenueIntentError.notSignedIn }
        let manager = SessionManager(session: session, store: store, authClient: auth, refreshEnabled: true)
        let client = LiveAPIClient(host: session.host, tokenProvider: manager)
        do {
            return try await client.get("/api/statistics/", query: [:], as: AdminDashboardStats.self)
        } catch APIError.authExpired {
            throw RevenueIntentError.notSignedIn
        }
    }

    static func money(_ d: Decimal) -> String { d.formatted(.currency(code: "USD")) }

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

struct TodaysRevenueIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's Revenue"
    static let description = IntentDescription("eSimplified's consolidated revenue so far today.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let stats = try await RevenueIntentSupport.fetch()
        let amount = RevenueIntentSupport.money(stats.revenueToday)
        return .result(value: amount, dialog: IntentDialog("eSimplified's revenue today is \(amount)."))
    }
}

struct YesterdayRevenueIntent: AppIntent {
    static let title: LocalizedStringResource = "Yesterday's Revenue"
    static let description = IntentDescription("eSimplified's consolidated revenue for yesterday.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let stats = try await RevenueIntentSupport.fetch()
        let amount = RevenueIntentSupport.money(stats.revenueYesterday)
        return .result(value: amount, dialog: IntentDialog("eSimplified's revenue yesterday was \(amount)."))
    }
}

struct RevenueVsYesterdayIntent: AppIntent {
    static let title: LocalizedStringResource = "Revenue vs Yesterday"
    static let description = IntentDescription("How today's eSimplified revenue compares to yesterday.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
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

/// Voice phrases. Every phrase must contain `\(.applicationName)`; the app's
/// alternative names (Info.plist `INAlternativeAppNames`) let "eSimplified"
/// match too.
struct EsimplifiedShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TodaysRevenueIntent(),
            phrases: [
                "What's today's revenue in \(.applicationName)",
                "Show today's revenue in \(.applicationName)",
                "How much did \(.applicationName) make today",
            ],
            shortTitle: "Today's Revenue",
            systemImageName: "dollarsign.circle"
        )
        AppShortcut(
            intent: YesterdayRevenueIntent(),
            phrases: [
                "What was yesterday's revenue in \(.applicationName)",
                "Show yesterday's revenue in \(.applicationName)",
            ],
            shortTitle: "Yesterday's Revenue",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: RevenueVsYesterdayIntent(),
            phrases: [
                "How is \(.applicationName) doing today",
                "Compare \(.applicationName) revenue to yesterday",
            ],
            shortTitle: "Revenue vs Yesterday",
            systemImageName: "chart.line.uptrend.xyaxis"
        )
    }
}
