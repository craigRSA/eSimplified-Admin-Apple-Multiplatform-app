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
    private(set) var deltaPercent: Decimal?
    private(set) var updatedAt: Date?

    func load(session: Session?) async {
        guard let session else { phase = .signedOut; return }
        if phase != .loaded { phase = .loading }
        do {
            let client = LiveAPIClient(host: session.host, accessToken: session.accessToken)
            let s = try await client.get("/api/statistics/", query: [:], as: AdminDashboardStats.self)
            today = s.revenueToday
            yesterday = s.revenueYesterday
            deltaPercent = s.deltaPercent
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
        VStack(alignment: .leading, spacing: 12) {
            switch revenue.phase {
            case .signedOut:
                Label("Not signed in", systemImage: "key.fill").font(.headline)
                Text("Open eSimplified to sign in.").font(.caption).foregroundStyle(.secondary)
            case .failed where revenue.phase != .loaded && revenue.today == 0:
                Label("Couldn't load", systemImage: "exclamationmark.triangle").font(.headline)
            default:
                Text("TODAY'S GROSS VOLUME")
                    .font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Fmt.money(revenue.today))
                        .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                    if let d = revenue.deltaPercent {
                        let up = d >= 0
                        Text("\(up ? "+" : "")\(d.formatted(.number.precision(.fractionLength(1))))%")
                            .font(.caption.weight(.semibold)).foregroundStyle(up ? .green : .red)
                    }
                }
                Text("vs \(Fmt.money(revenue.yesterday)) yesterday")
                    .font(.caption).foregroundStyle(.secondary)
                if let at = revenue.updatedAt {
                    Text("Updated \(at.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Divider()
            HStack {
                Button("Refresh") { Task { await revenue.load(session: model.session) } }
                Spacer()
                Button("Open") { NSApplication.shared.activate(ignoringOtherApps: true) }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .font(.callout)
        }
        .padding(14)
        .frame(width: 260)
        .task { await revenue.load(session: model.session) }
    }
}
#endif
