import SwiftUI
import EsimPulseKit

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
    var credentials: Credentials?

    init() {
        credentials = try? store.load()
    }

    func makeViewModel() -> DashboardViewModel? {
        guard let credentials else { return nil }
        return DashboardViewModel(client: LiveStatisticsClient(credentials: credentials))
    }

    func save(host: String, token: String) {
        let creds = Credentials(host: host, token: token)
        try? store.save(creds)
        credentials = creds
    }
}
