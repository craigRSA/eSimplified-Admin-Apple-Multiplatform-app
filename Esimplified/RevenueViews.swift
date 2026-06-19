import SwiftUI
import EsimplifiedKit

/// Shared revenue + delta display, used large (macOS window) and compact (iOS row).
struct RevenueDisplay: View {
    let viewModel: DashboardViewModel
    var large: Bool
    private let symbol = "$"

    var body: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case let .loaded(stats, stale):
            amountView(stats: stats, stale: stale)
        case .error(.authExpired):
            Text("Token expired — update in Settings")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
        case .error:
            Text("No data").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func amountView(stats: DashboardStats, stale: Bool) -> some View {
        let amount = Text("\(symbol)\(stats.revenueToday.formatted(.number.precision(.fractionLength(2))))")
            .font(.system(size: large ? 34 : 22, weight: .bold, design: .rounded))
            .opacity(stale ? 0.5 : 1)
        if large {
            VStack(spacing: 4) {
                amount
                DeltaLabel(deltaPercent: viewModel.deltaPercent)
            }
        } else {
            HStack {
                amount
                Spacer()
                DeltaLabel(deltaPercent: viewModel.deltaPercent)
            }
        }
    }
}

struct DeltaLabel: View {
    let deltaPercent: Decimal?

    var body: some View {
        if let delta = deltaPercent {
            let up = delta >= 0
            Label("\(delta.formatted(.number.precision(.fractionLength(1))))%",
                  systemImage: up ? "arrow.up" : "arrow.down")
                .foregroundStyle(up ? .green : .red)
                .font(.subheadline)
        }
    }
}
