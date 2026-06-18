import SwiftUI
import AppKit

struct FloatingWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.level = .floating
                window.titlebarAppearsTransparent = true
                window.isMovableByWindowBackground = true
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
