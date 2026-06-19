import SwiftUI
import EsimplifiedKit

@main
struct EsimplifiedAdminApp: App {
    @State private var model = AdminAppModel()

    var body: some Scene {
        WindowGroup {
            AdminRootView(model: model)
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        #endif
    }
}

@Observable
@MainActor
final class AdminAppModel {
    let store: SessionStore
    private(set) var session: Session?

    /// Tenant scope shared by all screens. `nil` = all tenants.
    var selectedTenant: Tenant?
    private(set) var tenants: [Tenant] = []

    // Client credentials injected from the build (Info.plist keys), never hardcoded.
    let clientID: String
    let clientSecret: String

    /// API host, configured at build time (Info.plist `ESPHost`) — never asked
    /// for in the UI. The root host; the app appends `/api/…` and `/auth/…`.
    let host: String

    init(store: SessionStore = KeychainSessionStore()) {
        self.store = store
        self.clientID = (Bundle.main.object(forInfoDictionaryKey: "ESPClientID") as? String) ?? ""
        self.clientSecret = (Bundle.main.object(forInfoDictionaryKey: "ESPClientSecret") as? String) ?? ""
        let configured = (Bundle.main.object(forInfoDictionaryKey: "ESPHost") as? String) ?? ""
        self.host = configured.isEmpty ? "https://live.esimplified.io" : configured
        self.session = try? store.load()
    }

    func authClient() -> LiveAuthClient {
        LiveAuthClient(clientID: clientID, clientSecret: clientSecret)
    }

    func adopt(_ session: Session) {
        try? store.save(session)
        self.session = session
    }

    func logout() {
        try? store.clear()
        session = nil
        tenants = []
        selectedTenant = nil
    }

    /// The schema name to scope queries by, or nil for all tenants.
    var tenantScope: String? { selectedTenant?.schemaName }

    func loadTenants() async {
        guard let session, tenants.isEmpty else { return }
        let client = LiveAPIClient(host: session.host, accessToken: session.accessToken)
        if let page = try? await client.get("/api/tenants/", query: ["limit": "1000", "order_by": "name"],
                                            as: TenantsPage.self) {
            tenants = page.tenants
        }
    }

    /// Sections allowed by the current token's scopes (Profile always shown).
    var sections: [AdminSection] {
        guard let session else { return [] }
        return AdminSection.allCases.filter { $0.scopeResource == nil || session.hasScope($0.scopeResource!) }
    }
}

struct AdminRootView: View {
    @Bindable var model: AdminAppModel

    var body: some View {
        if model.session == nil {
            LoginView(model: model)
        } else {
            AdminShell(model: model)
        }
    }
}
