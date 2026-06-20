import SwiftUI
import WidgetKit
import Charts
import EsimplifiedKit

struct RevenueWidgetView: View {
    @Environment(\.widgetFamily) private var family
    // WidgetKit puts `.placeholder` in here while rendering `placeholder(in:)`
    // (the gallery / first-paint state). We use it to skeletonise the figures so
    // a finance widget never shows the provider's sample numbers as if real.
    @Environment(\.redactionReasons) private var redactionReasons
    let entry: RevenueEntry
    private let symbol = "$"

    private var isPlaceholder: Bool { redactionReasons.contains(.placeholder) }

    var body: some View {
        switch entry.content {
        case let .revenue(today, deltaPercent, hToday, hYesterday):
            Group {
                if family == .systemMedium {
                    MediumRevenueView(symbol: symbol, today: today, deltaPercent: deltaPercent,
                                      hourlyToday: hToday, hourlyYesterday: hYesterday)
                } else {
                    SmallRevenueView(symbol: symbol, today: today, deltaPercent: deltaPercent)
                }
            }
            // Placeholder render: redact so the sample figures show as neutral
            // skeleton bars rather than convincing-but-fake revenue.
            .redacted(reason: isPlaceholder ? .placeholder : [])
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

    private var value: String { "\(symbol)\(today.formatted(.number.precision(.fractionLength(2))))" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                // Relative text style scales with Dynamic Type instead of a
                // fixed point size; never show fabricated figures in the
                // placeholder render.
                .font(.title.weight(.bold).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .privacySensitive()
            DeltaLabel(deltaPercent: deltaPercent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's revenue \(value)\(deltaPhrase(deltaPercent))")
    }
}

/// VoiceOver fragment for the percentage change, spoken as "up/down N percent"
/// so the direction never rests on color or an arrow glyph alone.
private func deltaPhrase(_ d: Decimal?) -> String {
    guard let d else { return "" }
    let dir = d >= 0 ? "up" : "down"
    let mag = d.magnitude.formatted(.number.precision(.fractionLength(1)))
    return ", \(dir) \(mag) percent versus yesterday"
}

private struct MediumRevenueView: View {
    let symbol: String
    let today: Decimal
    let deltaPercent: Decimal?
    let hourlyToday: [HourPoint]
    let hourlyYesterday: [HourPoint]

    private var value: String { "\(symbol)\(today.formatted(.number.precision(.fractionLength(2))))" }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Today").font(.caption).foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .privacySensitive()
                DeltaLabel(deltaPercent: deltaPercent)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Today's revenue \(value)\(deltaPhrase(deltaPercent))")
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
            // Arrow glyph carries the direction so it isn't color-only.
            Label("\(delta.formatted(.number.precision(.fractionLength(1))))%",
                  systemImage: up ? "arrow.up" : "arrow.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(up ? .green : .red)
                // The parent folds the delta into its combined label via
                // `deltaPhrase`, so keep this visual element out of VoiceOver.
                .accessibilityHidden(true)
        }
    }
}

/// Cumulative sales through the day (same as the app's hero): yesterday dashed,
/// today solid, today's line stopping at the current UTC hour. Cumulative points
/// come from EsimplifiedKit's `cumulativeHourly`, so the curve matches the app's
/// charts exactly — one shared implementation, nothing to keep in sync.
private struct HourlyChart: View {
    let today: [HourPoint]
    let yesterday: [HourPoint]

    /// The app's brand accent. The widget target has no global accent asset, so
    /// `.tint` here would fall back to the system accent and the identical chart
    /// would render a different colour than the app — hardcode the brand blue to
    /// keep the family resemblance. (Matches Assets.xcassets/AccentColor.)
    private static let brand = Color(red: 0.231, green: 0.510, blue: 0.965)

    var body: some View {
        let t = cumulativeHourly(today, cappedAt: utcHourFractionNow())
        let y = cumulativeHourly(yesterday)
        Chart {
            ForEach(y, id: \.hour) { p in
                LineMark(x: .value("Hour", p.hour), y: .value("Sales", p.total),
                         series: .value("Day", "Yesterday"))
                    .foregroundStyle(.gray).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            }
            ForEach(t, id: \.hour) { p in
                LineMark(x: .value("Hour", p.hour), y: .value("Sales", p.total),
                         series: .value("Day", "Today"))
                    .foregroundStyle(Self.brand).lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartXScale(domain: 0.0...24.0)
        .chartXAxis(.hidden).chartYAxis(.hidden)
        // The individual line marks are decorative; collapse the chart into one
        // element with a spoken summary instead of letting VoiceOver wade
        // through every plotted point.
        .accessibilityElement()
        .accessibilityLabel(summary(t, y))
    }

    /// Speaks the chart's takeaway: today's cumulative total and how it compares
    /// to yesterday's at the same point.
    private func summary(_ t: [CumulativeHourPoint], _ y: [CumulativeHourPoint]) -> String {
        let todayTotal = t.last?.total ?? 0
        let hoursIn = max(t.count - 1, 0)
        let cap = t.last?.hour ?? 24
        let yesterdaySoFar = y.last(where: { $0.hour <= cap })?.total ?? y.last?.total ?? 0
        let trend: String
        if yesterdaySoFar == 0 {
            trend = ""
        } else if todayTotal >= yesterdaySoFar {
            trend = ", ahead of yesterday at this hour"
        } else {
            trend = ", behind yesterday at this hour"
        }
        let total = todayTotal.formatted(.number.precision(.fractionLength(0)))
        return "Cumulative sales chart. Today \(total) through \(hoursIn) hours\(trend)."
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
