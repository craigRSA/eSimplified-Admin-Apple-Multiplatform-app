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
        Form {
            if twoFAToken == nil {
                Section("Sign in") {
                    TextField("Host", text: $host)
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        #endif
                    TextField("Username", text: $username)
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        #endif
                    SecureField("Password", text: $password)
                    Button("Sign in") { Task { await signIn() } }
                        .disabled(busy || host.isEmpty || username.isEmpty || password.isEmpty)
                }
            } else {
                Section("Two-factor code") {
                    TextField("6-digit code", text: $code)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Toggle("Remember this device", isOn: $rememberDevice)
                    Button("Verify") { Task { await verify() } }
                        .disabled(busy || code.count < 6)
                    Button("Cancel", role: .cancel) { twoFAToken = nil; code = "" }
                }
            }
            if let error {
                Text(error).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 460)
        .navigationTitle("eSimplified Admin")
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
