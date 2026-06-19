#if os(macOS)
import SwiftUI
import Combine
import AppKit
import EsimplifiedKit

/// The compact, always-on-top dashboard window content (macOS).
struct MacDashboard: View {
    let viewModel: DashboardViewModel
    @Binding var showSettings: Bool
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Today").font(.headline)
                Spacer()
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless)
            }
            RevenueDisplay(viewModel: viewModel, large: true)
            Spacer()
        }
        .padding()
        .task { await viewModel.refresh() }
        .onReceive(timer) { _ in Task { await viewModel.refresh() } }
    }
}

/// Host + token entry (macOS sheet / first-run).
struct ConnectionForm: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var token = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection").font(.headline)
            TextField("Admin host (https://…)", text: $host)
            SecureField("Bearer token", text: $token)
            HStack {
                Spacer()
                Button("Save") {
                    model.save(host: host.trimmingCharacters(in: .whitespaces),
                               token: token.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                .disabled(host.isEmpty || token.isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            host = model.credentials?.host ?? ""
            token = model.credentials?.token ?? ""
        }
    }
}

/// Configures the host window to float above other windows and be draggable by
/// its background. Uses `viewDidMoveToWindow` so the window is guaranteed attached.
struct FloatingWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { FloatingConfiguratorView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class FloatingConfiguratorView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.level = .floating
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
    }
}
#endif
