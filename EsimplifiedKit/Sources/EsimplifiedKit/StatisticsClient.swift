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
        components.path = "/api/statistics/"
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
