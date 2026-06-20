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

/// Cumulative today-vs-yesterday curve (same as the app's hero): yesterday
/// dashed over the full day, today solid with a dot on the latest point so a
/// single early-day value is still visible.
private struct HourlyChart: View {
    let today: [HourPoint]
    let yesterday: [HourPoint]

    var body: some View {
        let t = cumulative(today)
        let y = cumulative(yesterday)
        Chart {
            ForEach(y, id: \.hour) { p in
                LineMark(x: .value("Hour", p.hour), y: .value("Revenue", p.total),
                         series: .value("Day", "Yesterday"))
                    .foregroundStyle(.gray).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(t, id: \.hour) { p in
                LineMark(x: .value("Hour", p.hour), y: .value("Revenue", p.total),
                         series: .value("Day", "Today"))
                    .foregroundStyle(.tint).lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
            }
            if let last = t.last {
                PointMark(x: .value("Hour", last.hour), y: .value("Revenue", last.total))
                    .foregroundStyle(.tint).symbolSize(22)
            }
        }
        .chartXScale(domain: 0...23)
        .chartXAxis(.hidden).chartYAxis(.hidden)
    }

    private func cumulative(_ points: [HourPoint]) -> [(hour: Int, total: Double)] {
        var running = 0.0
        return points.sorted { $0.hour < $1.hour }.map { p in
            running += (p.revenue as NSDecimalNumber).doubleValue
            return (p.hour, running)
        }
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
