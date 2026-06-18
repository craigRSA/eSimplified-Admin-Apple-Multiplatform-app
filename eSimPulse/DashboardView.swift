import SwiftUI
import Combine
import EsimPulseKit

struct RootView: View {
    @Bindable var model: AppModel
    @State private var showSettings = false

    var body: some View {
        Group {
            if let vm = model.viewModel {
                DashboardView(viewModel: vm, showSettings: $showSettings)
                    .id(ObjectIdentifier(vm))
            } else {
                SettingsView(model: model)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model)
        }
    }
}

struct DashboardView: View {
    let viewModel: DashboardViewModel
    @Binding var showSettings: Bool
    private let symbol = "$"
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Today").font(.headline)
                Spacer()
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless)
            }
            content
            Spacer()
        }
        .padding()
        .task { await viewModel.refresh() }
        .onReceive(timer) { _ in Task { await viewModel.refresh() } }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case let .loaded(stats, stale):
            VStack(spacing: 4) {
                Text("\(symbol)\(stats.revenueToday.formatted(.number.precision(.fractionLength(2))))")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .opacity(stale ? 0.5 : 1)
                deltaView
            }
        case .error(.authExpired):
            Text("Token expired — update in Settings")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
        case .error:
            Text("No data").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var deltaView: some View {
        if let delta = viewModel.deltaPercent {
            let up = delta >= 0
            Label("\(delta.formatted(.number.precision(.fractionLength(1))))%",
                  systemImage: up ? "arrow.up" : "arrow.down")
                .foregroundStyle(up ? .green : .red)
                .font(.subheadline)
        }
    }
}
