import SwiftUI
import CoreImage.CIFilterBuiltins
import EsimplifiedKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct TwoFactorSetupView: View {
    let host: String
    private let client: LiveTwoFactorClient
    @Environment(\.dismiss) private var dismiss

    @State private var setup: TOTPSetup?
    @State private var code = ""
    @State private var status: String?
    @State private var enabled = false
    @State private var loadFailed = false
    @State private var busy = false

    @FocusState private var codeFocused: Bool

    init(host: String, tokenProvider: any AccessTokenProviding) {
        self.host = host
        self.client = LiveTwoFactorClient(host: host, tokenProvider: tokenProvider)
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    SectionHeader("Two-factor authentication", eyebrow: "Security")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let setup {
                        enrollment(setup)
                    } else if loadFailed {
                        failureCard
                    } else {
                        loadingCard
                    }
                }
                .frame(maxWidth: 360)
                .padding(Spacing.xl)
            }
        }
        .frame(minWidth: 320, minHeight: 360)
    }

    // MARK: - Enrollment

    @ViewBuilder private func enrollment(_ setup: TOTPSetup) -> some View {
        let secret = setup.secret ?? Self.secret(from: setup.otpauthURL)
        VStack(spacing: Spacing.lg) {
            if let image = Self.qrImage(from: setup.otpauthURL) {
                image.resizable().interpolation(.none)
                    .frame(width: 180, height: 180)
                    .padding(Spacing.sm)
                    .background(.white, in: .rect(cornerRadius: Radius.chip))
                    .accessibilityLabel(secret.map { "Two-factor QR code. Enrollment secret: \($0)" }
                                        ?? "Two-factor enrollment QR code")
            }

            if let secret {
                VStack(spacing: Spacing.xs) {
                    Text("Or enter this secret manually")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(secret)
                        .font(.callout.monospaced()).textSelection(.enabled)
                        .multilineTextAlignment(.center)
                        .accessibilityLabel("Enrollment secret: \(secret)")
                }
            }

            Text("Scan the QR in your authenticator app, then enter the 6-digit code.")
                .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)

            TextField("6-digit code", text: $code)
                .font(.title3.monospacedDigit()).tracking(4)
                .multilineTextAlignment(.center)
                .textContentType(.oneTimeCode)
                .focused($codeFocused)
                .submitLabel(.go)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .onSubmit { if code.count >= 6 { Task { await verify() } } }
                .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.md)
                .background(.thinMaterial, in: .rect(cornerRadius: Radius.chip))

            statusRow

            Button {
                Task { await verify() }
            } label: {
                HStack(spacing: Spacing.sm) {
                    if busy { ProgressView().controlSize(.small) }
                    Text(busy ? "Enabling…" : "Enable").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.glassProminent)
            .disabled(busy || code.count < 6)

            Button(enabled ? "Done" : "Close") { dismiss() }
                .font(.callout).buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .glassCard(radius: Radius.card, padding: Spacing.xl)
        .onAppear { codeFocused = true }
    }

    // MARK: - Loading / failure

    private var loadingCard: some View {
        VStack(spacing: Spacing.md) {
            ProgressView("Starting setup…")
            Button("Close") { dismiss() }
                .font(.callout).buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .glassCard(radius: Radius.card, padding: Spacing.xl)
        .task { await begin() }
    }

    private var failureCard: some View {
        VStack(spacing: Spacing.md) {
            ContentUnavailableView {
                Label("Couldn't start setup", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text("We couldn't reach the server to begin two-factor enrollment.")
            } actions: {
                Button("Try Again") { Task { await begin() } }
                    .buttonStyle(.glassProminent)
            }
            Button("Close") { dismiss() }
                .font(.callout).buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .glassCard(radius: Radius.card, padding: Spacing.xl)
    }

    @ViewBuilder private var statusRow: some View {
        if let status {
            Label(status, systemImage: enabled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(enabled ? Color.positive : Color.negative)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("\(enabled ? "Success" : "Error"): \(status)")
        }
    }

    private func begin() async {
        guard !busy, setup == nil else { return }
        busy = true; defer { busy = false }
        loadFailed = false
        do { setup = try await client.beginSetup() }
        catch { loadFailed = true; status = nil }
    }

    private func verify() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            try await client.verify(code: code)
            // Show confirmation and let the user dismiss — an immediate dismiss()
            // here would tear the view down before the message is ever visible.
            enabled = true
            status = "Two-factor enabled. You can close this."
        } catch {
            enabled = false
            status = "That code didn't work."
        }
    }

    // MARK: - QR rendering (no third-party dependency)

    private static func qrImage(from string: String) -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        #if os(macOS)
        return Image(nsImage: NSImage(cgImage: cg, size: .zero))
        #else
        return Image(uiImage: UIImage(cgImage: cg))
        #endif
    }

    private static func secret(from otpauth: String) -> String? {
        URLComponents(string: otpauth)?.queryItems?.first(where: { $0.name == "secret" })?.value
    }
}
