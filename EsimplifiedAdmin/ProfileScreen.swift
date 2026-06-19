import SwiftUI
import EsimplifiedKit

struct ProfileScreen: View {
    let session: Session
    var onLogout: () -> Void

    @State private var me: MeUser?
    @State private var totpEnabled: Bool?
    @State private var error: String?
    @State private var status: String?
    @State private var disableCode = ""
    @State private var busy = false
    @State private var showSetup = false

    private var twoFA: LiveTwoFactorClient {
        LiveTwoFactorClient(host: session.host, accessToken: session.accessToken)
    }

    var body: some View {
        Form {
            Section("Account") {
                if let me {
                    LabeledContent("Name", value: me.displayName)
                    if !me.email.isEmpty { LabeledContent("Email", value: me.email) }
                    LabeledContent("Username", value: me.username)
                    LabeledContent("Account type", value: me.accountType.capitalized)
                    if me.isSuperuser { Label("Superuser", systemImage: "star.fill").foregroundStyle(.orange) }
                    else if me.isStaff { Label("Staff", systemImage: "person.badge.key").foregroundStyle(.blue) }
                } else {
                    ProgressView()
                }
            }

            if let me {
                Section("Access") {
                    LabeledContent("All-tenant access", value: me.allTenantAccess ? "Yes" : "No")
                    if !me.tenantNames.isEmpty { LabeledContent("Tenants", value: "\(me.tenantNames.count)") }
                    LabeledContent("Permissions", value: "\(me.effectiveScopes.count) scopes")
                }
            }

            Section("Security") {
                switch totpEnabled {
                case .some(true):
                    Label("Two-factor authentication is on", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    TextField("6-digit code to disable", text: $disableCode)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Button("Turn off two-factor", role: .destructive) { Task { await disable() } }
                        .disabled(busy || disableCode.count < 6)
                case .some(false):
                    Label("Two-factor authentication is off", systemImage: "shield.slash").foregroundStyle(.secondary)
                    Button("Set up two-factor authentication") { showSetup = true }
                case nil:
                    ProgressView()
                }
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            }

            Section {
                Button("Log out", role: .destructive, action: onLogout)
            }

            if let error { Text(error).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .navigationTitle("Profile")
        .sheet(isPresented: $showSetup, onDismiss: { Task { await loadStatus() } }) {
            TwoFactorSetupView(host: session.host, accessToken: session.accessToken)
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let client = LiveAPIClient(host: session.host, accessToken: session.accessToken)
            me = try await client.get("/api/me/", query: [:], as: MeUser.self)
        } catch let e as APIError {
            error = adminErrorMessage(e)
        } catch {
            self.error = "Unexpected error."
        }
        await loadStatus()
    }

    private func loadStatus() async {
        totpEnabled = (try? await twoFA.status()) ?? false
    }

    private func disable() async {
        busy = true; defer { busy = false }
        status = nil
        do {
            try await twoFA.disable(code: disableCode)
            disableCode = ""
            status = "Two-factor turned off."
            await loadStatus()
        } catch {
            status = "That code didn't work."
        }
    }
}
