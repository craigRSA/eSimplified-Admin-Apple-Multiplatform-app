import WidgetKit
import Foundation
import EsimplifiedKit

/// What the widget renders for a given timeline entry.
enum RevenueContent: Equatable {
    case revenue(today: Decimal, deltaPercent: Decimal?, series: [DayRevenue])
    case needsAuth
    case unavailable
}

struct RevenueEntry: TimelineEntry {
    let date: Date
    let content: RevenueContent
}

/// Drives the widget timeline: reads the Admin app's signed-in session from the
/// shared Keychain access group, refreshes the OAuth token when it has expired,
/// and fetches the latest stats itself — so the widget stays current with the
/// app closed.
struct RevenueProvider: TimelineProvider {
    private let store = KeychainSessionStore()

    /// Minutes between widget refreshes. WidgetKit treats this as a hint and
    /// may space refreshes further apart under system budget pressure.
    private static let refreshMinutes = 20

    func placeholder(in context: Context) -> RevenueEntry {
        RevenueEntry(date: Date(), content: .revenue(today: Decimal(string: "1523.45")!,
                                                      deltaPercent: Decimal(string: "8.6"),
                                                      series: Self.sampleSeries))
    }

    func getSnapshot(in context: Context, completion: @escaping (RevenueEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task { completion(await fetchEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RevenueEntry>) -> Void) {
        Task {
            let entry = await fetchEntry()
            let next = Calendar.current.date(byAdding: .minute, value: Self.refreshMinutes, to: Date())
                ?? Date().addingTimeInterval(Double(Self.refreshMinutes) * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func fetchEntry() async -> RevenueEntry {
        guard var session = try? store.load() else {
            return RevenueEntry(date: Date(), content: .needsAuth)
        }
        // The widget runs with the app closed, so refresh an expired token itself.
        if session.expiresAt <= Date() {
            guard let auth = authClient(),
                  let refreshed = try? await auth.refresh(host: session.host,
                                                          refreshToken: session.refreshToken) else {
                return RevenueEntry(date: Date(), content: .needsAuth)
            }
            try? store.save(refreshed)
            session = refreshed
        }
        let client = LiveAPIClient(host: session.host, accessToken: session.accessToken)
        do {
            let stats = try await client.get("/api/statistics/", query: [:], as: AdminDashboardStats.self)
            return RevenueEntry(date: Date(),
                                content: .revenue(today: stats.revenueToday,
                                                  deltaPercent: stats.deltaPercent,
                                                  series: stats.revenuePerDate))
        } catch APIError.authExpired {
            return RevenueEntry(date: Date(), content: .needsAuth)
        } catch {
            return RevenueEntry(date: Date(), content: .unavailable)
        }
    }

    /// Client credentials injected into the widget's Info.plist (same Secrets
    /// xcconfig as the app); needed to refresh the OAuth token.
    private func authClient() -> LiveAuthClient? {
        let id = (Bundle.main.object(forInfoDictionaryKey: "ESPClientID") as? String) ?? ""
        let secret = (Bundle.main.object(forInfoDictionaryKey: "ESPClientSecret") as? String) ?? ""
        guard !id.isEmpty, !secret.isEmpty else { return nil }
        return LiveAuthClient(clientID: id, clientSecret: secret)
    }

    private static let sampleSeries: [DayRevenue] = [
        DayRevenue(date: "2026-06-11", revenue: Decimal(string: "1100.00")!),
        DayRevenue(date: "2026-06-12", revenue: Decimal(string: "1250.50")!),
        DayRevenue(date: "2026-06-13", revenue: Decimal(string: "1402.10")!),
        DayRevenue(date: "2026-06-14", revenue: Decimal(string: "1290.00")!),
        DayRevenue(date: "2026-06-15", revenue: Decimal(string: "1480.75")!),
        DayRevenue(date: "2026-06-16", revenue: Decimal(string: "1402.10")!),
        DayRevenue(date: "2026-06-17", revenue: Decimal(string: "1523.45")!),
    ]
}
