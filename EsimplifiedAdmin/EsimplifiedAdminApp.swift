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

    // Client credentials injected from the build (Info.plist keys), never hardcoded.
    let clientID: String
    let clientSecret: String

    init(store: SessionStore = KeychainSessionStore()) {
        self.store = store
        self.clientID = (Bundle.main.object(forInfoDictionaryKey: "ESPClientID") as? String) ?? ""
        self.clientSecret = (Bundle.main.object(forInfoDictionaryKey: "ESPClientSecret") as? String) ?? ""
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
