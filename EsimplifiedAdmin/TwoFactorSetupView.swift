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
    let accessToken: String
    private let client: LiveTwoFactorClient
    @Environment(\.dismiss) private var dismiss

    @State private var setup: TOTPSetup?
    @State private var code = ""
    @State private var status: String?
    @State private var busy = false

    init(host: String, accessToken: String) {
        self.host = host
        self.accessToken = accessToken
        self.client = LiveTwoFactorClient(host: host, accessToken: accessToken)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Set up two-factor authentication").font(.headline)
            if let setup {
                if let image = Self.qrImage(from: setup.otpauthURL) {
                    image.resizable().interpolation(.none).frame(width: 180, height: 180)
                }
                if let secret = setup.secret ?? Self.secret(from: setup.otpauthURL) {
                    Text("Secret: \(secret)").font(.caption).textSelection(.enabled)
                }
                Text("Scan the QR in your authenticator app, then enter the 6-digit code.")
                    .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
                TextField("6-digit code", text: $code)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .frame(maxWidth: 160)
                Button("Enable") { Task { await verify() } }.disabled(busy || code.count < 6)
            } else {
                ProgressView().task { await begin() }
            }
            if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            Button("Close") { dismiss() }
        }
        .padding()
        .frame(minWidth: 280)
    }

    private func begin() async {
        guard !busy, setup == nil else { return }
        busy = true; defer { busy = false }
        do { setup = try await client.beginSetup() }
        catch { status = "Couldn't start setup." }
    }

    private func verify() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            try await client.verify(code: code)
            // Show confirmation and let the user dismiss — an immediate dismiss()
            // here would tear the view down before the message is ever visible.
            status = "Two-factor enabled. You can close this."
        } catch {
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
