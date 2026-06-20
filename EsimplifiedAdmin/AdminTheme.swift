import SwiftUI

// MARK: - Backdrop

/// A quiet, brand-tinted gradient that sits behind scrolling content so the
/// Liquid Glass surfaces have something to refract. Deliberately low-contrast —
/// the data is the subject, not the background.
struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.07, blue: 0.12),
                Color(red: 0.03, green: 0.04, blue: 0.07)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .overlay(alignment: .top) {
            // A faint accent bloom anchored to the top, where the eye lands first.
            RadialGradient(
                colors: [Color.accentColor.opacity(0.16), .clear],
                center: .top, startRadius: 0, endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glass card

private struct GlassCard: ViewModifier {
    var radius: CGFloat = 18
    var padding: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: radius))
    }
}

extension View {
    /// Wraps content in a padded Liquid Glass card. One radius/padding system
    /// across the whole app so surfaces feel like one material.
    func glassCard(radius: CGFloat = 18, padding: CGFloat = 18) -> some View {
        modifier(GlassCard(radius: radius, padding: padding))
    }
}

// MARK: - Section header

/// A small eyebrow + title used above grouped content. Uppercase tracking gives
/// it a quiet, utilitarian register that lets the numbers below it lead.
struct SectionHeader: View {
    let title: String
    var eyebrow: String?
    init(_ title: String, eyebrow: String? = nil) { self.title = title; self.eyebrow = eyebrow }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.semibold)).tracking(0.8)
                    .foregroundStyle(.secondary)
            }
            Text(title).font(.title3.weight(.semibold))
        }
    }
}

// MARK: - UTC clock

/// Live UTC clock for the toolbar — the dashboard's hourly series is in UTC,
/// so this anchors it no matter where you are.
struct UTCClock: View {
    var body: some View {
        // Display shows minutes only, so update once a minute — a per-second
        // ticker on the nav chrome re-renders the container and cancels the
        // detail screen's in-flight load on iPhone.
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            Label(Self.formatter.string(from: ctx.date), systemImage: "clock")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
        }
    }
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "HH:mm 'UTC'"
        return f
    }()
}

// MARK: - Reliable load trigger

/// Loads on appear and whenever `id` changes, using an **unstructured** Task.
///
/// On iPhone `NavigationSplitView` collapses, and navigating to a detail screen
/// cancels its `.task` mid-flight — which silently dropped our network loads
/// ("not connected" / stuck spinner). An unstructured Task isn't tied to the
/// view's lifecycle, so the load completes regardless of navigation churn.
private struct ReloadTrigger<ID: Equatable>: ViewModifier {
    let id: ID
    let action: () async -> Void
    @State private var loadedID: ID?
    func body(content: Content) -> some View {
        content
            .onAppear { if loadedID != id { loadedID = id; Task { await action() } } }
            .onChange(of: id) { _, newID in loadedID = newID; Task { await action() } }
    }
}

extension View {
    /// Runs `action` on appear and when `id` changes, surviving the `.task`
    /// cancellation that iPhone `NavigationSplitView` triggers on navigation.
    func reload<ID: Equatable>(on id: ID, _ action: @escaping () async -> Void) -> some View {
        modifier(ReloadTrigger(id: id, action: action))
    }
}

// MARK: - Auto-refresh

/// App-wide auto-refresh interval (seconds; 0 = off), persisted across launches.
enum RefreshInterval {
    static let options: [Int] = [0, 15, 30, 60, 300]
    static func label(_ s: Int) -> String {
        switch s {
        case 0: "Off"
        case 60: "1 min"
        case 300: "5 min"
        default: "\(s)s"
        }
    }
}

/// Toolbar menu that picks the auto-refresh cadence. Bound to shared @AppStorage
/// so every screen honours the same choice.
struct RefreshIntervalMenu: View {
    @Binding var seconds: Int
    var body: some View {
        Menu {
            Picker("Auto-refresh", selection: $seconds) {
                ForEach(RefreshInterval.options, id: \.self) { Text(RefreshInterval.label($0)).tag($0) }
            }
        } label: {
            Label(seconds == 0 ? "Auto-refresh" : "Every \(RefreshInterval.label(seconds))",
                  systemImage: seconds == 0 ? "timer" : "timer.circle.fill")
        }
    }
}

private struct AutoRefresh: ViewModifier {
    @AppStorage("autoRefreshSeconds") private var seconds = 0
    let action: () async -> Void
    func body(content: Content) -> some View {
        content
            .task(id: seconds) {
                guard seconds > 0 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(Double(seconds)))
                    if Task.isCancelled { break }
                    await action()
                }
            }
    }
}

extension View {
    /// Runs `action` on the shared auto-refresh cadence (no-op while set to Off).
    /// The interval control itself lives in the shell toolbar (`RefreshIntervalMenu`).
    func autoRefresh(_ action: @escaping () async -> Void) -> some View {
        modifier(AutoRefresh(action: action))
    }
}
