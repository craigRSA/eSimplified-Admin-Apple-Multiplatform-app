import SwiftUI
import EsimplifiedKit
#if os(macOS)
import AppKit
#endif

private struct TokenProviderKey: EnvironmentKey {
    static let defaultValue: any AccessTokenProviding = StaticTokenProvider("")
}
extension EnvironmentValues {
    var tokenProvider: any AccessTokenProviding {
        get { self[TokenProviderKey.self] }
        set { self[TokenProviderKey.self] = newValue }
    }
}

#if os(macOS)
/// Keeps the app (and its menu-bar item) alive after the last window closes.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
#endif

@main
struct EsimplifiedAdminApp: App {
    @State private var model = AdminAppModel()
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var menu = MenuBarRevenue()
    #endif

    var body: some Scene {
        WindowGroup {
            AdminRootView(model: model)
                .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        .commands { AdminCommands(model: model) }
        #endif

        #if os(macOS)
        Settings {
            SettingsView(model: model)
        }

        MenuBarExtra {
            MenuBarPanel(model: model, revenue: menu)
        } label: {
            MenuBarLabel(revenue: menu)
                .task(id: model.session?.accessToken) {
                    await menu.load(session: model.session, provider: model.sessionManager)
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(300))
                        if Task.isCancelled { break }
                        await menu.load(session: model.session, provider: model.sessionManager)
                    }
                }
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

@Observable
@MainActor
final class AdminAppModel {
    let store: SessionStore
    private(set) var session: Session?
    let sessionManager: SessionManager
    private(set) var biometricEnabled: Bool

    /// Tenant scope shared by all screens. `nil` = all tenants.
    var selectedTenant: Tenant?
    private(set) var tenants: [Tenant] = []

    /// Selected sidebar section — lifted here so the ⌘1…⌘9 menu commands can
    /// drive the same selection the shell binds to.
    var selection: AdminSection?

    // Client credentials injected from the build (Info.plist keys), never hardcoded.
    let clientID: String
    let clientSecret: String

    /// API host, configured at build time (Info.plist `ESPHost`) — never asked
    /// for in the UI. The root host; the app appends `/api/…` and `/auth/…`.
    let host: String

    init(store: SessionStore = KeychainSessionStore()) {
        self.store = store
        let id = (Bundle.main.object(forInfoDictionaryKey: "ESPClientID") as? String) ?? ""
        let secret = (Bundle.main.object(forInfoDictionaryKey: "ESPClientSecret") as? String) ?? ""
        self.clientID = id
        self.clientSecret = secret
        let configured = (Bundle.main.object(forInfoDictionaryKey: "ESPHost") as? String) ?? ""
        self.host = configured.isEmpty ? "https://live.esimplified.io" : configured

        let loaded = try? store.load()
        self.session = loaded
        let enabled = store.biometricEnabled()
        self.biometricEnabled = enabled

        // Refresh is allowed on macOS always; on iOS only when biometric sign-in
        // is enabled (otherwise the session is ephemeral — sign out on expiry).
        #if os(macOS)
        let refreshEnabled = true
        #else
        let refreshEnabled = enabled
        #endif

        self.sessionManager = SessionManager(
            session: loaded, store: store,
            authClient: LiveAuthClient(clientID: id, clientSecret: secret),
            refreshEnabled: refreshEnabled)

        // The manager is the single writer of `session`; mirror its changes to the
        // observable on the main actor (also clears tenants on sign-out).
        let mgr = sessionManager
        Task { await mgr.setOnChange { [weak self] newSession in
            Task { @MainActor in
                self?.session = newSession
                if newSession == nil { self?.tenants = []; self?.tenantLogos = [:]; self?.selectedTenant = nil }
            }
        } }
        // Wire up the real isEnabled closure now that self is fully initialised.
        #if os(iOS)
        lock = AppLockController(isEnabled: { [weak self] in self?.biometricEnabled ?? false })
        #endif
    }

    func authClient() -> LiveAuthClient { LiveAuthClient(clientID: clientID, clientSecret: clientSecret) }

    func adopt(_ session: Session) {
        Task { await sessionManager.adopt(session) }   // persists + fires onChange → sets self.session
    }

    func logout() {
        // Clears the session only. `biometricEnabled` is intentionally preserved
        // across logout: it's a device-level preference ("require biometric to open
        // this app"), not session state, so the next sign-in on this device re-arms
        // the gate automatically — matching how system apps treat such preferences.
        Task { await sessionManager.clear() }            // clears store + fires onChange(nil)
    }

    func setBiometricEnabled(_ enabled: Bool) {
        biometricEnabled = enabled
        try? store.setBiometricEnabled(enabled)
        #if os(iOS)
        Task { await sessionManager.setRefreshEnabled(enabled) }
        #endif
    }

    #if os(iOS)
    /// Set once in `init()` — IUO avoids a throwaway placeholder allocation.
    private(set) var lock: AppLockController!
    var offerBiometricEnrollment = false
    #endif

    /// The schema name to scope queries by, or nil for all tenants.
    var tenantScope: String? { selectedTenant?.schemaName }

    /// `schema_name → small logo URL`, built once from the loaded tenants so order
    /// rows can show each tenant's logo without a per-row lookup.
    private(set) var tenantLogos: [String: URL] = [:]

    func loadTenants() async {
        guard let session, tenants.isEmpty else { return }
        let client = LiveAPIClient(host: session.host, tokenProvider: sessionManager)
        if let page = try? await client.get("/api/tenants/", query: ["limit": "1000", "order_by": "name"],
                                            as: TenantsPage.self) {
            tenants = page.tenants
            tenantLogos = Dictionary(page.tenants.compactMap { t in t.logoSmall.map { (t.schemaName.lowercased(), $0) } },
                                     uniquingKeysWith: { first, _ in first })
            // Mirror the web: with exactly one tenant, scope to it automatically so
            // tenant-gated screens (Customers, customer search) work immediately.
            if selectedTenant == nil, tenants.count == 1 { selectedTenant = tenants.first }
        }
    }

    /// Sections allowed by the current token's scopes (Profile always shown).
    /// `.agentOrder` is excluded until it's actually built — it had no detail
    /// screen and always landed on a "Coming soon" placeholder.
    var sections: [AdminSection] {
        guard let session else { return [] }
        return AdminSection.allCases.filter {
            $0 != .agentOrder && ($0.scopeResource == nil || session.hasScope($0.scopeResource!))
        }
    }
}

private struct TenantLogosKey: EnvironmentKey {
    static let defaultValue: [String: URL] = [:]
}
extension EnvironmentValues {
    /// `schema_name → small logo URL` for the order rows' tenant tiles.
    var tenantLogos: [String: URL] {
        get { self[TenantLogosKey.self] }
        set { self[TenantLogosKey.self] = newValue }
    }
}

struct AdminRootView: View {
    @Bindable var model: AdminAppModel

    var body: some View {
        if model.session == nil {
            LoginView(model: model)
        } else {
            #if os(iOS)
            let kind = BiometryKind.cached
            AdminShell(model: model)
                .environment(\.tokenProvider, model.sessionManager)
                .environment(\.tenantLogos, model.tenantLogos)
                .modifier(LockContainer(controller: model.lock, onUsePassword: { model.logout() }))
                .alert("Enable \(kind.label)?", isPresented: $model.offerBiometricEnrollment) {
                    Button("Enable") { model.setBiometricEnabled(true) }
                    Button("Not Now", role: .cancel) {}
                } message: {
                    Text("Require \(kind.label) each time you open the app. Your session stays signed in in the background.")
                }
            #else
            AdminShell(model: model)
                .environment(\.tokenProvider, model.sessionManager)
                .environment(\.tenantLogos, model.tenantLogos)
            #endif
        }
    }
}

#if os(macOS)
/// Menu-bar commands: ⌘R refresh (routed to the focused screen) and ⌘1…⌘9 to
/// jump sections. ⌘, opens Settings automatically.
struct AdminCommands: Commands {
    let model: AdminAppModel
    @FocusedValue(\.refreshAction) private var refresh

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Refresh") { refresh?() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(refresh == nil)
        }
        CommandMenu("Go") {
            ForEach(Array(model.sections.prefix(9).enumerated()), id: \.element) { index, section in
                Button(section.title) { model.selection = section }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }
}

/// Standard ⌘, Settings: the auto-refresh cadence, the configured host, and a
/// place for the destructive Log Out action.
struct SettingsView: View {
    @Bindable var model: AdminAppModel
    @State private var confirmLogout = false

    var body: some View {
        Form {
            Section("Data") {
                LabeledContent("Host", value: model.host)
            }
            Section("Account") {
                if let s = model.session {
                    LabeledContent("Account type", value: s.accountType.capitalized)
                }
                Button("Log Out…", role: .destructive) { confirmLogout = true }
                    .confirmationDialog("Log out of eSimplified?", isPresented: $confirmLogout) {
                        Button("Log Out", role: .destructive) { model.logout() }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 260)
    }
}
#endif
