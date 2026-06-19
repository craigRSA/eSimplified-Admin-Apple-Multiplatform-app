import SwiftUI
import Charts
import EsimplifiedKit

struct DashboardScreen: View {
    let session: Session

    @State private var phase: Phase = .loading

    enum Phase { case loading, loaded(AdminDashboardStats), failed(String) }

    var body: some View {
        ScrollView {
            switch phase {
            case .loading:
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, minHeight: 300)
            case let .failed(message):
                ContentUnavailableView("Couldn't load the dashboard", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
                    .frame(minHeight: 300)
            case let .loaded(stats):
                content(stats)
            }
        }
        .navigationTitle("Dashboard")
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder private func content(_ s: AdminDashboardStats) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HeroRevenue(today: s.revenueToday, deltaPercent: s.deltaPercent)

            if !s.revenuePerDate.isEmpty {
                RevenueTrend(series: s.revenuePerDate)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                StatCard(title: "Total revenue", value: Money.full(s.revenue), icon: "dollarsign.circle", tint: .green)
                StatCard(title: "This month", value: Money.full(s.revenueCurrentMonth), icon: "calendar", tint: .blue)
                StatCard(title: "Last month", value: Money.full(s.revenueLastMonth), icon: "calendar.badge.clock", tint: .indigo)
                StatCard(title: "Yesterday", value: Money.full(s.revenueYesterday), icon: "clock.arrow.circlepath", tint: .teal)
                StatCard(title: "Success orders", value: s.successOrders.formatted(), icon: "checkmark.seal", tint: .green)
                StatCard(title: "Customers", value: s.customers.formatted(), icon: "person.2", tint: .orange)
                StatCard(title: "Tenants", value: s.tenants.formatted(), icon: "building.2", tint: .purple)
                StatCard(title: "Avg order", value: Money.full(s.averageOrderValue), icon: "cart", tint: .pink)
            }
        }
        .padding(20)
    }

    private func load() async {
        do {
            let client = LiveAPIClient(host: session.host, accessToken: session.accessToken)
            let stats = try await client.get("/api/statistics/", query: ["date_range": "last_7_days"],
                                             as: AdminDashboardStats.self)
            phase = .loaded(stats)
        } catch let error as APIError {
            phase = .failed(Self.describe(error))
        } catch {
            phase = .failed("Unexpected error.")
        }
    }

    private static func describe(_ error: APIError) -> String {
        switch error {
        case .unreachable: "Couldn't reach the server."
        case .authExpired: "Your session expired — sign in again."
        case .notFound: "The statistics endpoint wasn't found."
        case let .server(code): "Server error (\(code))."
        case let .requestFailed(code, message): message.map { "Server (\(code)): \($0)" } ?? "Request failed (\(code))."
        case .decoding: "Couldn't read the server response."
        }
    }
}

// MARK: - Pieces

private struct HeroRevenue: View {
    let today: Decimal
    let deltaPercent: Decimal?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today").font(.subheadline).foregroundStyle(.secondary)
            Text(Money.full(today))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.5)
            if let delta = deltaPercent {
                let up = delta >= 0
                Label("\(delta.formatted(.number.precision(.fractionLength(1))))% vs yesterday",
                      systemImage: up ? "arrow.up.right" : "arrow.down.right")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(up ? .green : .red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct RevenueTrend: View {
    let series: [DayRevenue]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Revenue — last \(series.count) days").font(.headline)
            Chart(series, id: \.date) { day in
                AreaMark(x: .value("Date", day.date),
                         y: .value("Revenue", (day.revenue as NSDecimalNumber).doubleValue))
                    .foregroundStyle(.linearGradient(colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.02)],
                                                     startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", day.date),
                         y: .value("Revenue", (day.revenue as NSDecimalNumber).doubleValue))
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.catmullRom)
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .frame(height: 200)
        }
        .padding(20)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint).font(.title3)
            Text(value).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }
}

enum Money {
    static func full(_ d: Decimal) -> String {
        "$" + d.formatted(.number.precision(.fractionLength(2)).grouping(.automatic))
    }
}
