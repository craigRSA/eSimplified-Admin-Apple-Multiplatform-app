import Foundation

/// Current hour (0–23) in UTC. The dashboard, widget, and menu bar all reckon
/// "to date" in UTC (matching the backend's `revenue_per_hour_*` series), so they
/// share this instead of each rolling their own.
public func utcHourNow() -> Int {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return cal.component(.hour, from: Date())
}

/// Current UTC time-of-day as a fractional hour (08:30 → 8.5) — where "now" sits on
/// the 0…24 hourly axis, so a cumulative "today" line can stop partway through the
/// current hour rather than running to its end.
public func utcHourFractionNow() -> Double {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let c = cal.dateComponents([.hour, .minute, .second], from: Date())
    return Double(c.hour ?? 0) + (Double(c.minute ?? 0) * 60 + Double(c.second ?? 0)) / 3600
}

/// A point on the cumulative hourly-revenue curve: an x position on the 0…24 axis
/// and the running total through that point.
public struct CumulativeHourPoint: Equatable, Sendable {
    public let hour: Double
    public let total: Double
    public init(hour: Double, total: Double) { self.hour = hour; self.total = total }
}

/// Accumulates per-hour increments into a running total, plotted at the end of each
/// hour and prefixed with a 0 origin (so a single hour still draws a line).
///
/// `cappedAt` — the current UTC fraction, for the in-progress "today" series — stops
/// the current hour at "now" (08:30 → x 8.5) instead of its end; pass nil for a
/// complete day ("yesterday"). Shared by the dashboard hero, the widget, and the
/// menu bar so the curve is computed identically and can't drift between them.
public func cumulativeHourly(_ src: [HourPoint], cappedAt now: Double? = nil) -> [CumulativeHourPoint] {
    var out = [CumulativeHourPoint(hour: 0, total: 0)]
    var running = 0.0
    for p in src.sorted(by: { $0.hour < $1.hour }) {
        running += (p.revenue as NSDecimalNumber).doubleValue
        let end = Double(p.hour + 1)
        out.append(CumulativeHourPoint(hour: now.map { Swift.min(end, $0) } ?? end, total: running))
    }
    return out
}
