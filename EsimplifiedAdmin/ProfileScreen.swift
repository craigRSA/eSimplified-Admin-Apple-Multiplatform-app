import SwiftUI
import EsimplifiedKit
#if os(iOS)
import UIKit
#endif

struct ProfileScreen: View {
    let session: Session
    var onLogout: () -> Void
    var biometricEnabled: Bool = false
    var setBiometricEnabled: (Bool) -> Void = { _ in }

    /// Honest tri-state: we only know 2FA is on/off when the status call returns.
    /// A failed fetch leaves us in `.unknown`, never coerced to "off".
    private enum TOTPState { case unknown, on, off }

    @Environment(\.tokenProvider) private var tokenProvider

    @State private var me: MeUser?
    @State private var totp: TOTPState = .unknown
    @State private var statusLoaded = false
    @State private var error: String?
    @State private var status: String?
    @State private var statusOK = false
    @State private var disableCode = ""
    @State private var busy = false
    @State private var showSetup = false
    @State private var confirmLogout = false
    @State private var confirmDisable = false

    private var twoFA: LiveTwoFactorClient {
        LiveTwoFactorClient(host: session.host, tokenProvider: tokenProvider)
    }

    var body: some View {
        Form {
            Section("Account") {
                if let me {
                    LabeledContent("Name", value: me.displayName)
                    if !me.email.isEmpty { LabeledContent("Email", value: me.email) }
                    LabeledContent("Username", value: me.username)
                    LabeledContent("Account type", value: me.accountType.capitalized)
                    if me.isSuperuser {
                        Label("Superuser", systemImage: "star.fill")
                            .foregroundStyle(.warning)
                            .accessibilityLabel("Role: Superuser")
                    } else if me.isStaff {
                        Label("Staff", systemImage: "person.badge.key")
                            .foregroundStyle(.blue)
                            .accessibilityLabel("Role: Staff")
                    }
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
                securityContent
                statusRow
            }

            #if os(iOS)
            Section("App lock") {
                let kind = BiometryKind.cached
                Toggle("Require \(kind.label) to open", isOn: Binding(
                    get: { biometricEnabled },
                    set: { setBiometricEnabled($0) }))
                if biometricEnabled {
                    Text("The app locks on launch and after a few minutes in the background. Your session refreshes in the background.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            #endif

            Section {
                Button("Log out", role: .destructive) { confirmLogout = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Profile")
        .confirmationDialog("Log out of eSimplified Admin?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Log Out", role: .destructive, action: onLogout)
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Turn off two-factor authentication?", isPresented: $confirmDisable, titleVisibility: .visible) {
            Button("Turn Off", role: .destructive) { Task { await disable() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This makes your account easier to compromise. The 6-digit code you entered will be used to confirm.")
        }
        .sheet(isPresented: $showSetup, onDismiss: { Task { await loadStatus() } }) {
            TwoFactorSetupView(host: session.host, tokenProvider: tokenProvider)
        }
        .reload(on: 0) { await load() }
    }

    @ViewBuilder private var securityContent: some View {
        switch totp {
        case .on:
            Label("Two-factor authentication is on", systemImage: "checkmark.shield.fill")
                .foregroundStyle(.positive)
                .accessibilityLabel("Two-factor authentication: On")
            TextField("6-digit code to disable", text: $disableCode)
                .textContentType(.oneTimeCode)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Button("Turn off two-factor", role: .destructive) { confirmDisable = true }
                .disabled(busy || disableCode.count < 6)
        case .off:
            Label("Two-factor authentication is off", systemImage: "shield.slash")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Two-factor authentication: Off")
            Button("Set up two-factor authentication") { showSetup = true }
        case .unknown:
            if statusLoaded {
                Label("Two-factor status unavailable", systemImage: "questionmark.circle")
                    .foregroundStyle(.warning)
                    .accessibilityLabel("Two-factor authentication: status unknown")
                Button("Retry") { Task { await loadStatus() } }
            } else {
                ProgressView()
            }
        }
    }

    @ViewBuilder private var statusRow: some View {
        if let status {
            Label(status, systemImage: statusOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(statusOK ? Color.positive : Color.negative)
                .accessibilityLabel("\(statusOK ? "Success" : "Error"): \(status)")
        }
        if let error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.negative)
                .accessibilityLabel("Error: \(error)")
        }
    }

    private func load() async {
        do {
            let client = LiveAPIClient(host: session.host, tokenProvider: tokenProvider)
            me = try await client.get("/api/me/", query: [:], as: MeUser.self)
        } catch is CancellationError {
            // View navigated away mid-load — not a real error.
        } catch let e as APIError {
            error = adminErrorMessage(e)
        } catch {
            self.error = "Unexpected error."
        }
        await loadStatus()
    }

    private func loadStatus() async {
        do {
            // Keep the genuine value; only a real failure leaves us "unknown".
            totp = try await twoFA.status() ? .on : .off
        } catch is CancellationError {
            // Navigated away mid-load — leave whatever we had.
        } catch {
            totp = .unknown
        }
        statusLoaded = true
    }

    private func disable() async {
        busy = true; defer { busy = false }
        status = nil
        do {
            try await twoFA.disable(code: disableCode)
            disableCode = ""
            statusOK = true
            status = "Two-factor turned off."
            haptic(success: true)
            await loadStatus()
        } catch {
            statusOK = false
            status = "That code didn't work."
            haptic(success: false)
        }
    }

    private func haptic(success: Bool) {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error)
        #endif
    }
}
