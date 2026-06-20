import SwiftUI
import WidgetKit
import Charts
import EsimplifiedKit

struct RevenueWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RevenueEntry
    private let symbol = "$"

    var body: some View {
        switch entry.content {
        case let .revenue(today, deltaPercent, hToday, hYesterday):
            if family == .systemMedium {
                MediumRevenueView(symbol: symbol, today: today, deltaPercent: deltaPercent,
                                  hourlyToday: hToday, hourlyYesterday: hYesterday)
            } else {
                SmallRevenueView(symbol: symbol, today: today, deltaPercent: deltaPercent)
            }
        case .needsAuth:
            PlaceholderMessage(icon: "key.fill", text: "Open eSimplified to sign in")
        case .unavailable:
            PlaceholderMessage(icon: "wifi.slash", text: "No data")
        }
    }
}

private struct SmallRevenueView: View {
    let symbol: String
    let today: Decimal
    let deltaPercent: Decimal?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("\(symbol)\(today.formatted(.number.precision(.fractionLength(2))))")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            DeltaLabel(deltaPercent: deltaPercent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct MediumRevenueView: View {
    let symbol: String
    let today: Decimal
    let deltaPercent: Decimal?
    let hourlyToday: [HourPoint]
    let hourlyYesterday: [HourPoint]

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Today").font(.caption).foregroundStyle(.secondary)
                Text("\(symbol)\(today.formatted(.number.precision(.fractionLength(2))))")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                DeltaLabel(deltaPercent: deltaPercent)
            }
            Spacer(minLength: 0)
            HourlyChart(today: hourlyToday, yesterday: hourlyYesterday)
                .frame(width: 140)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct DeltaLabel: View {
    let deltaPercent: Decimal?

    var body: some View {
        if let delta = deltaPercent {
            let up = delta >= 0
            Label("\(delta.formatted(.number.precision(.fractionLength(1))))%",
                  systemImage: up ? "arrow.up" : "arrow.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(up ? .green : .red)
        }
    }
}

/// Cumulative sales through the day (same as the app's hero): yesterday dashed,
/// today solid with a dot so a single early-day value still shows. Per-hour
/// increments are accumulated and plotted at each hour's end, with a 0 start.
private struct HourlyChart: View {
    let today: [HourPoint]
    let yesterday: [HourPoint]

    var body: some View {
        let t = points(today)
        let y = points(yesterday)
        Chart {
            ForEach(y, id: \.x) { p in
                LineMark(x: .value("Hour", p.x), y: .value("Sales", p.v),
                         series: .value("Day", "Yesterday"))
                    .foregroundStyle(.gray).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            }
            ForEach(t, id: \.x) { p in
                LineMark(x: .value("Hour", p.x), y: .value("Sales", p.v),
                         series: .value("Day", "Today"))
                    .foregroundStyle(.tint).lineStyle(StrokeStyle(lineWidth: 2))
                    .symbol(Circle())
            }
        }
        .chartXScale(domain: 0...24)
        .chartXAxis(.hidden).chartYAxis(.hidden)
    }

    private func points(_ src: [HourPoint]) -> [(x: Int, v: Double)] {
        var out: [(x: Int, v: Double)] = [(0, 0)]
        var running = 0.0
        for p in src.sorted(by: { $0.hour < $1.hour }) {
            running += (p.revenue as NSDecimalNumber).doubleValue
            out.append((p.hour + 1, running))
        }
        return out
    }
}

private struct PlaceholderMessage: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
