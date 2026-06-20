#if os(macOS)
import SwiftUI
import AppKit
import EsimplifiedKit

/// Drives the macOS menu-bar item: today's revenue, refreshed on a timer while
/// the app runs. Reads the signed-in session from `AdminAppModel`.
@Observable @MainActor
final class MenuBarRevenue {
    enum Phase: Equatable { case idle, loading, loaded, signedOut, failed }
    private(set) var phase: Phase = .idle
    private(set) var today: Decimal = 0
    private(set) var yesterday: Decimal = 0
    /// Yesterday's revenue through the current UTC hour — the like-for-like base the
    /// delta compares against (nil before the hourly series ships).
    private(set) var yesterdayToDate: Decimal?
    private(set) var deltaPercent: Decimal?
    private(set) var updatedAt: Date?

    func load(session: Session?, provider: any AccessTokenProviding) async {
        guard let session else { phase = .signedOut; return }
        if phase != .loaded { phase = .loading }
        do {
            let client = LiveAPIClient(host: session.host, tokenProvider: provider)
            let s = try await client.get("/api/statistics/", query: [:], as: AdminDashboardStats.self)
            today = s.revenueToday
            yesterday = s.revenueYesterday
            // Compare today-so-far against yesterday through the same UTC hour — the
            // dashboard hero's "to date" basis — not the full prior day.
            let toDate = s.revenueYesterdayThroughHour(utcHourNow())
            yesterdayToDate = toDate
            deltaPercent = AdminDashboardStats.change(today, vs: toDate ?? yesterday)
            updatedAt = Date()
            phase = .loaded
        } catch is CancellationError {
            // ignore
        } catch {
            if phase != .loaded { phase = .failed }
        }
    }
}

/// The text shown in the menu bar itself.
struct MenuBarLabel: View {
    let revenue: MenuBarRevenue
    var body: some View {
        if revenue.phase == .loaded || revenue.today != 0 {
            Text(Fmt.money(revenue.today))
        } else {
            Image(systemName: "dollarsign.circle")
        }
    }
}

/// The dropdown panel.
struct MenuBarPanel: View {
    let model: AdminAppModel
    let revenue: MenuBarRevenue

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            switch revenue.phase {
            case .signedOut:
                Label("Not signed in", systemImage: "key.fill").font(.headline)
                Text("Open eSimplified to sign in.").font(.caption).foregroundStyle(.secondary)
            case .failed where revenue.phase != .loaded && revenue.today == 0:
                Label("Couldn't load", systemImage: "exclamationmark.triangle").font(.headline)
            case .loading where revenue.today == 0:
                Overline("Today's gross volume")
                // A labeled skeleton instead of a bare "$0.00" flash while the
                // first stats fetch is in flight.
                SkeletonBar(width: 150, height: 30)
                SkeletonBar(width: 110, height: 12)
                    .accessibilityElement()
                    .accessibilityLabel("Loading today's revenue")
            default:
                Overline("Today's gross volume")
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(Fmt.money(revenue.today))
                        .font(.display(.title)).monospacedDigit()
                    TrendDelta(percent: revenue.deltaPercent, font: .subheadline.weight(.semibold))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(volumeAccessibilityLabel)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let toDate = revenue.yesterdayToDate {
                        Text("vs \(Fmt.money(toDate)) yesterday (to date)")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("vs \(Fmt.money(revenue.yesterday)) yesterday")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let at = revenue.updatedAt {
                        Text("Updated \(at.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            Divider()
            HStack {
                Button("Refresh") { Task { await revenue.load(session: model.session, provider: model.sessionManager) } }
                    .accessibilityLabel("Refresh revenue")
                Spacer()
                Button("Open") { NSApplication.shared.activate(ignoringOtherApps: true) }
                    .accessibilityLabel("Open eSimplified")
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .accessibilityLabel("Quit eSimplified")
            }
            .font(.callout)
        }
        .padding(Spacing.lg)
        .frame(width: 260)
        .task { await revenue.load(session: model.session, provider: model.sessionManager) }
    }

    /// One coherent VoiceOver phrase for the hero figure + change + freshness.
    private var volumeAccessibilityLabel: String {
        var parts = ["Today's gross volume \(Fmt.money(revenue.today))"]
        if let d = revenue.deltaPercent {
            let dir = d >= 0 ? "up" : "down"
            let mag = d.magnitude.formatted(.number.precision(.fractionLength(1)))
            let base = revenue.yesterdayToDate != nil ? "versus yesterday to date" : "versus yesterday"
            parts.append("\(dir) \(mag) percent \(base)")
        }
        if let at = revenue.updatedAt {
            parts.append("updated \(at.formatted(date: .omitted, time: .shortened))")
        }
        return parts.joined(separator: ", ")
    }
}

/// The eyebrow above the hero figure. Reuses `SectionHeader`'s exact overline
/// styling (uppercase, tracked caption) without a redundant title line, and is
/// hidden from VoiceOver since the hero element already announces it.
private struct Overline: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).eyebrow()
            .accessibilityHidden(true)
    }
}
#endif
