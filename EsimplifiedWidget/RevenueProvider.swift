import WidgetKit
import Foundation
import EsimplifiedKit

/// What the widget renders for a given timeline entry.
enum RevenueContent: Equatable {
    case revenue(today: Decimal, deltaPercent: Decimal?,
                 hourlyToday: [HourPoint], hourlyYesterday: [HourPoint])
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
                                                      hourlyToday: Self.sampleToday,
                                                      hourlyYesterday: Self.sampleYesterday))
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
        guard let session = try? store.load() else {
            return RevenueEntry(date: Date(), content: .needsAuth)
        }
        guard let auth = authClient() else {
            return RevenueEntry(date: Date(), content: .needsAuth)
        }
        let manager = SessionManager(session: session, store: store, authClient: auth, refreshEnabled: true)
        let client = LiveAPIClient(host: session.host, tokenProvider: manager)
        do {
            let stats = try await client.get("/api/statistics/", query: [:], as: AdminDashboardStats.self)
            // Compare today-so-far against yesterday through the same UTC hour — the
            // dashboard hero's "to date" basis — falling back to the full-day delta.
            let delta = stats.deltaPercentToDate(currentHour: utcHourNow()) ?? stats.deltaPercent
            return RevenueEntry(date: Date(),
                                content: .revenue(today: stats.revenueToday,
                                                  deltaPercent: delta,
                                                  hourlyToday: stats.revenuePerHourToday,
                                                  hourlyYesterday: stats.revenuePerHourYesterday))
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

    private static let sampleToday: [HourPoint] = (0...10).map {
        HourPoint(hour: $0, revenue: Decimal(120 + $0 * 95))
    }
    private static let sampleYesterday: [HourPoint] = (0...23).map {
        HourPoint(hour: $0, revenue: Decimal(95 + $0 * 70))
    }
}
