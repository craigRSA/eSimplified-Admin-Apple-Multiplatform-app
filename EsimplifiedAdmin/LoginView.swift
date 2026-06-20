import SwiftUI
import EsimplifiedKit
import LocalAuthentication

struct LoginView: View {
    @Bindable var model: AdminAppModel

    private var host: String { model.host }
    @State private var username = ""
    @State private var password = ""
    @State private var twoFAToken: String?
    @State private var code = ""
    @State private var rememberDevice = true
    @State private var error: String?
    @State private var busy = false

    /// The fields the cursor can land in. The login form and the 2FA form share
    /// the same enum so `@FocusState` survives the swap between the two cards.
    private enum Field { case username, password, code }
    @FocusState private var focus: Field?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: Spacing.xl) {
                header
                Group {
                    if twoFAToken == nil { credentialsCard } else { twoFactorCard }
                }
                .frame(maxWidth: 380)
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.negative)
                        .frame(maxWidth: 380, alignment: .leading)
                        .transition(.opacity)
                        .accessibilityLabel("Error: \(error)")
                }
            }
            .padding(Spacing.xxl)
        }
        .animation(reduceMotion ? nil : .snappy, value: twoFAToken)
        .animation(reduceMotion ? nil : .snappy, value: error)
        .onAppear { if twoFAToken == nil { focus = .username } }
        .onChange(of: twoFAToken) { _, token in focus = token == nil ? .username : .code }
    }

    private var header: some View {
        VStack(spacing: Spacing.md) {
            Image("BrandMark").resizable().scaledToFit().frame(height: 56)
                .shadow(color: .accentColor.opacity(0.35), radius: 18, y: 6)
                .accessibilityHidden(true)
            Text("eSimplified Admin").font(.title.weight(.semibold))
            Text(twoFAToken == nil ? "Sign in to your console" : "Enter your authenticator code")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var credentialsCard: some View {
        VStack(spacing: Spacing.md) {
            field(systemImage: "person") {
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .focused($focus, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                    #if os(iOS)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    #endif
            }
            field(systemImage: "lock") {
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await signIn() } }
            }
            primaryButton(title: "Sign in", busyTitle: "Signing in…") { await signIn() }
                .disabled(busy || host.isEmpty || username.isEmpty || password.isEmpty)
        }
        .glassCard(radius: Radius.card, padding: Spacing.xl)
    }

    private var twoFactorCard: some View {
        VStack(spacing: Spacing.md) {
            field(systemImage: "number") {
                TextField("6-digit code", text: $code)
                    .font(.title3.monospacedDigit()).tracking(4)
                    .textContentType(.oneTimeCode)
                    .focused($focus, equals: .code)
                    .submitLabel(.go)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .onSubmit { Task { await verify() } }
            }
            Toggle("Remember this device", isOn: $rememberDevice)
                .font(.callout).tint(.accentColor)
            primaryButton(title: "Verify", busyTitle: "Verifying…") { await verify() }
                .disabled(busy || code.count < 6)
            Button("Use a different account") { twoFAToken = nil; code = "" }
                .font(.callout).buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .glassCard(radius: Radius.card, padding: Spacing.xl)
    }

    @ViewBuilder private func field<Content: View>(systemImage: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 20)
                .accessibilityHidden(true)
            content().textFieldStyle(.plain)
        }
        .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.md)
        .background(.thinMaterial, in: .rect(cornerRadius: Radius.chip))
    }

    private func primaryButton(title: String, busyTitle: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: Spacing.sm) {
                if busy { ProgressView().controlSize(.small) }
                Text(busy ? busyTitle : title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.glassProminent)
    }

    private func signIn() async {
        busy = true; defer { busy = false }
        error = nil
        do {
            let trusted = try? model.store.trustedDeviceToken(host: host)
            let result = try await model.authClient().login(username: username, password: password,
                                                            host: host, trustedDeviceToken: trusted)
            switch result {
            case let .session(session): finish(session)
            case let .needs2FA(token): twoFAToken = token
            }
        } catch let e as APIError {
            self.error = adminErrorMessage(e)
        } catch {
            self.error = "Sign-in failed. Check your details and try again."
        }
    }

    private func verify() async {
        guard let token = twoFAToken else { return }
        busy = true; defer { busy = false }
        error = nil
        do {
            let (session, trusted) = try await model.authClient().verify2FA(host: host, twoFAToken: token,
                                                                            code: code, rememberDevice: rememberDevice)
            if rememberDevice, let trusted {
                try? model.store.saveTrustedDeviceToken(trusted, host: host)
            }
            finish(session)
        } catch let e as APIError where e == .unreachable {
            self.error = "Couldn't reach the server — check your connection."
        } catch {
            self.error = "That code didn't work. Try again."
        }
    }

    private func finish(_ session: Session) {
        guard session.accountType == "human" else {
            error = "This account can't sign in here."
            return
        }
        model.adopt(session)
        #if os(iOS)
        // set synchronously before adopt's async session update mounts AdminShell, so the alert is present on first render
        if !model.biometricEnabled, LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
            model.offerBiometricEnrollment = true
        }
        #endif
    }
}
