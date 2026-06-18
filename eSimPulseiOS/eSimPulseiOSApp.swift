import SwiftUI
import EsimPulseKit

@main
struct eSimPulseiOSApp: App {
    @State private var model = AppState()

    var body: some Scene {
        WindowGroup {
            RootScreen(model: model)
        }
    }
}

@Observable
@MainActor
final class AppState {
    let store = KeychainCredentialStore()
    private(set) var credentials: Credentials?
    private(set) var viewModel: DashboardViewModel?

    init() {
        let loaded = try? store.load()
        credentials = loaded
        viewModel = loaded.map { DashboardViewModel(client: LiveStatisticsClient(credentials: $0)) }
    }

    func save(host: String, token: String) {
        let creds = Credentials(host: host, token: token)
        try? store.save(creds)
        credentials = creds
        viewModel = DashboardViewModel(client: LiveStatisticsClient(credentials: creds))
    }
}

struct RootScreen: View {
    @Bindable var model: AppState
    @State private var host = ""
    @State private var token = ""
    private let symbol = "$"

    var body: some View {
        NavigationStack {
            Form {
                if let vm = model.viewModel {
                    Section("Today") {
                        TodaySection(viewModel: vm, symbol: symbol)
                    }
                }
                Section("Connection") {
                    TextField("Admin host (https://…)", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Bearer token", text: $token)
                    Button("Save") {
                        model.save(host: host.trimmingCharacters(in: .whitespaces),
                                   token: token.trimmingCharacters(in: .whitespaces))
                    }
                    .disabled(host.isEmpty || token.isEmpty)
                }
                Section {
                    Text("Add the eSim Pulse widget to your Home Screen or Lock Screen for a glanceable number.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("eSim Pulse")
            .onAppear {
                host = model.credentials?.host ?? ""
                token = model.credentials?.token ?? ""
            }
        }
    }
}

private struct TodaySection: View {
    let viewModel: DashboardViewModel
    let symbol: String

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
            case let .loaded(stats, _):
                HStack {
                    Text("\(symbol)\(stats.revenueToday.formatted(.number.precision(.fractionLength(2))))")
                        .font(.title.weight(.bold))
                    Spacer()
                    if let delta = viewModel.deltaPercent {
                        let up = delta >= 0
                        Label("\(delta.formatted(.number.precision(.fractionLength(1))))%",
                              systemImage: up ? "arrow.up" : "arrow.down")
                            .foregroundStyle(up ? .green : .red)
                            .font(.subheadline)
                    }
                }
            case .error(.authExpired):
                Text("Token expired — update below").foregroundStyle(.secondary)
            case .error:
                Text("No data").foregroundStyle(.secondary)
            }
        }
        .task { await viewModel.refresh() }
    }
}
