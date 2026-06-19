import SwiftUI
import EsimplifiedKit

@main
struct eSimPulseApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("eSim Pulse", id: "main") {
            RootView(model: model)
                .frame(width: 280, height: 200)
                .background(FloatingWindowConfigurator())
        }
        .windowResizability(.contentSize)
    }
}

@Observable
@MainActor
final class AppModel {
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
