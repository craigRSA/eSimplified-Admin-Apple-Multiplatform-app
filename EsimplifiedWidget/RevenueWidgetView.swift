import SwiftUI
import WidgetKit
import EsimplifiedKit

struct RevenueWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RevenueEntry
    private let symbol = "$"

    var body: some View {
        switch entry.content {
        case let .revenue(today, deltaPercent, series):
            if family == .systemMedium {
                MediumRevenueView(symbol: symbol, today: today, deltaPercent: deltaPercent, series: series)
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
    let series: [DayRevenue]

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
            Sparkline(values: series.map(\.revenue))
                .frame(width: 130)
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

/// Dependency-free 7-point line chart drawn with a `Path`.
private struct Sparkline: View {
    let values: [Decimal]

    var body: some View {
        GeometryReader { geo in
            let points = normalizedPoints(in: geo.size)
            ZStack {
                if points.count >= 2 {
                    Path { path in
                        path.move(to: points[0])
                        for p in points.dropFirst() { path.addLine(to: p) }
                    }
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    if let last = points.last {
                        Circle().fill(.tint).frame(width: 5, height: 5).position(last)
                    }
                }
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let nums = values.map { ($0 as NSDecimalNumber).doubleValue }
        guard nums.count >= 2 else { return [] }
        let minV = nums.min() ?? 0
        let maxV = nums.max() ?? 1
        let range = maxV - minV
        let stepX = size.width / CGFloat(nums.count - 1)
        return nums.enumerated().map { i, v in
            let y: CGFloat = range == 0
                ? size.height / 2
                : size.height * (1 - CGFloat((v - minV) / range))
            return CGPoint(x: CGFloat(i) * stepX, y: y)
        }
    }
}
