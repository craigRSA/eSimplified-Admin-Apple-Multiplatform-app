import SwiftUI
import EsimplifiedKit

@main
struct EsimplifiedApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        #if os(macOS)
        Window("eSimplified", id: "main") {
            RootView(model: model)
                .frame(width: 280, height: 220)
                .background(FloatingWindowConfigurator())
        }
        .windowResizability(.contentSize)
        #else
        WindowGroup {
            RootView(model: model)
        }
        #endif
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

struct RootView: View {
    @Bindable var model: AppModel
    @State private var showSettings = false

    var body: some View {
        #if os(macOS)
        Group {
            if let vm = model.viewModel {
                MacDashboard(viewModel: vm, showSettings: $showSettings)
                    .id(ObjectIdentifier(vm))
            } else {
                ConnectionForm(model: model)
            }
        }
        .sheet(isPresented: $showSettings) {
            ConnectionForm(model: model)
        }
        #else
        PhoneRoot(model: model)
        #endif
    }
}
