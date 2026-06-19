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
        guard case let .loaded(stats, _) = state else { return nil }
        return stats.deltaPercent
    }
}
