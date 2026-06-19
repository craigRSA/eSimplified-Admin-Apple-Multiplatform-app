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

/// Drives the widget timeline: reads the Bearer token from the shared Keychain
/// access group (written by the host app) and fetches the latest stats itself,
/// so the widget stays current with the app closed.
struct RevenueProvider: TimelineProvider {
    private let store = KeychainCredentialStore()

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
        guard let credentials = try? store.load() else {
            return RevenueEntry(date: Date(), content: .needsAuth)
        }
        let client = LiveStatisticsClient(credentials: credentials)
        do {
            let stats = try await client.fetch(dateRange: .last7Days)
            return RevenueEntry(date: Date(),
                                content: .revenue(today: stats.revenueToday,
                                                  deltaPercent: stats.deltaPercent,
                                                  series: stats.revenuePerDate))
        } catch StatsError.authExpired {
            return RevenueEntry(date: Date(), content: .needsAuth)
        } catch {
            return RevenueEntry(date: Date(), content: .unavailable)
        }
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
