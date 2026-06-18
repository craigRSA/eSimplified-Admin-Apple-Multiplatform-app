import SwiftUI
import AppKit

/// Configures the host window to float above other windows and be draggable by
/// its background. Uses `viewDidMoveToWindow` so the window is guaranteed
/// attached when applied (a deferred `DispatchQueue.main.async` can fire before
/// the window exists on cold launch and silently no-op).
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
