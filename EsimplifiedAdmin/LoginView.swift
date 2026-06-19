import SwiftUI
import EsimplifiedKit

struct LoginView: View {
    @Bindable var model: AdminAppModel

    @State private var host = "https://live.esimplified.io"
    @State private var username = ""
    @State private var password = ""
    @State private var twoFAToken: String?
    @State private var code = ""
    @State private var rememberDevice = true
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 22) {
                header
                Group {
                    if twoFAToken == nil { credentialsCard } else { twoFactorCard }
                }
                .frame(maxWidth: 380)
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.red)
                        .frame(maxWidth: 380, alignment: .leading)
                        .transition(.opacity)
                }
            }
            .padding(28)
        }
        .animation(.snappy, value: twoFAToken)
        .animation(.snappy, value: error)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image("BrandMark").resizable().scaledToFit().frame(height: 56)
                .shadow(color: .accentColor.opacity(0.35), radius: 18, y: 6)
            Text("eSimplified Admin").font(.title.weight(.semibold))
            Text(twoFAToken == nil ? "Sign in to your console" : "Enter your authenticator code")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var credentialsCard: some View {
        VStack(spacing: 14) {
            field(systemImage: "globe") {
                TextField("Host", text: $host)
                    #if os(iOS)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    #endif
            }
            field(systemImage: "person") {
                TextField("Username", text: $username)
                    #if os(iOS)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    #endif
            }
            field(systemImage: "lock") {
                SecureField("Password", text: $password)
                    .onSubmit { Task { await signIn() } }
            }
            primaryButton(title: "Sign in", busyTitle: "Signing in…") { await signIn() }
                .disabled(busy || host.isEmpty || username.isEmpty || password.isEmpty)
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private var twoFactorCard: some View {
        VStack(spacing: 14) {
            field(systemImage: "number") {
                TextField("6-digit code", text: $code)
                    .font(.title3.monospacedDigit()).tracking(4)
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
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    @ViewBuilder private func field<Content: View>(systemImage: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 20)
            content().textFieldStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.thinMaterial, in: .rect(cornerRadius: 12))
    }

    private func primaryButton(title: String, busyTitle: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 8) {
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
            self.error = Self.message(for: e)
        } catch {
            self.error = "Sign-in failed. Check your details and try again."
        }
    }

    private static func message(for error: APIError) -> String {
        switch error {
        case .unreachable: "Couldn't reach the server — check the host and your connection."
        case let .requestFailed(status, serverMessage):
            if let serverMessage { "Server (\(status)): \(serverMessage)" }
            else { "Sign-in rejected (HTTP \(status))." }
        case .authExpired: "Sign-in rejected (401)."
        case .notFound: "Endpoint not found — check the host."
        case .server(let code): "Server error (\(code))."
        case .decoding: "Unexpected response from the server."
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
    }
}
