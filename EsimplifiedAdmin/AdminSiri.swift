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
    static let title: LocalizedStringResource = "Today"
    static let description = IntentDescription("Today's overview total so far.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let stats = try await RevenueIntentSupport.fetch()
        let amount = RevenueIntentSupport.money(stats.revenueToday)
        return .result(value: amount, dialog: IntentDialog("Sales so far today: \(amount)."))
    }
}

struct YesterdayRevenueIntent: AppIntent {
    static let title: LocalizedStringResource = "Yesterday"
    static let description = IntentDescription("Yesterday's overview total.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let stats = try await RevenueIntentSupport.fetch()
        let amount = RevenueIntentSupport.money(stats.revenueYesterday)
        return .result(value: amount, dialog: IntentDialog("Sales yesterday: \(amount)."))
    }
}

struct RevenueVsYesterdayIntent: AppIntent {
    static let title: LocalizedStringResource = "Today vs Yesterday"
    static let description = IntentDescription("How today compares to yesterday.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let stats = try await RevenueIntentSupport.fetch()
        let today = RevenueIntentSupport.money(stats.revenueToday)
        guard let delta = stats.deltaPercent else {
            return .result(dialog: IntentDialog("Sales so far today: \(today)."))
        }
        let up = delta >= 0
        let pct = abs(delta).formatted(.number.precision(.fractionLength(1)))
        return .result(dialog: IntentDialog(
            "Sales today are \(today), \(up ? "up" : "down") \(pct) percent from yesterday."))
    }
}

/// Voice phrases. Every phrase must contain `\(.applicationName)`; the app's
/// alternative names (Info.plist `INAlternativeAppNames`) let "eSimplified"
/// match too. Wording stays broad — "today", "numbers", "how are we doing" —
/// not revenue jargon.
struct EsimplifiedShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TodaysRevenueIntent(),
            phrases: [
                "How are sales today in \(.applicationName)",
                "How's sales today in \(.applicationName)",
                "\(.applicationName) how are sales today",
                "\(.applicationName) sales today",
                "Sales today in \(.applicationName)",
                "What are sales today in \(.applicationName)",
                "How's today in \(.applicationName)",
                "Today's numbers in \(.applicationName)",
                "What's today looking like in \(.applicationName)",
                "Give me today in \(.applicationName)",
            ],
            shortTitle: "Today",
            systemImageName: "dollarsign.circle"
        )
        AppShortcut(
            intent: YesterdayRevenueIntent(),
            phrases: [
                "Sales yesterday in \(.applicationName)",
                "What were sales yesterday in \(.applicationName)",
                "How was yesterday in \(.applicationName)",
                "Yesterday's numbers in \(.applicationName)",
                "What did we do yesterday in \(.applicationName)",
            ],
            shortTitle: "Yesterday",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: RevenueVsYesterdayIntent(),
            phrases: [
                "How are we doing in \(.applicationName)",
                "Compare today to yesterday in \(.applicationName)",
                "Am I up or down in \(.applicationName)",
                "Today versus yesterday in \(.applicationName)",
            ],
            shortTitle: "Today vs Yesterday",
            systemImageName: "chart.line.uptrend.xyaxis"
        )
    }
}
