import SwiftUI
import Combine

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
    func glassCard(radius: CGFloat = Radius.card, padding: CGFloat = Spacing.lg) -> some View {
        modifier(GlassCard(radius: radius, padding: padding))
    }
}

// MARK: - Design tokens

/// One spacing rhythm for the whole app (replaces the ~14 ad-hoc values that
/// had crept in). Use these instead of bare numbers.
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 22
    static let xxl: CGFloat = 28
}

/// One radius scale: a card radius, a chip/field radius, and a tooltip radius.
/// Everything that draws a rounded rect routes through these.
enum Radius {
    static let card: CGFloat = 18
    static let chip: CGFloat = 12
    static let tooltip: CGFloat = 8
}

extension ShapeStyle where Self == Color {
    /// Semantic status colors. Defined on `ShapeStyle where Self == Color` so the
    /// leading-dot form works in `.foregroundStyle(.positive)` / `.tint(.negative)`
    /// AND the explicit `Color.positive` form resolves too.
    /// IMPORTANT: meaning must never rest on color alone — always pair these with
    /// a glyph or text (see `TrendDelta`, `StatusBadge`).
    static var positive: Color { .green }
    static var negative: Color { .red }
    static var warning: Color { .orange }
}

/// Maps a backend status / eUICC state string to its semantic color — the single
/// source of truth so every screen tints "refunded", "pending", etc. the same.
enum StatusStyle {
    static func color(_ status: String) -> Color {
        switch status.lowercased() {
        case "success", "approved", "active", "enabled", "installed", "released": .positive
        case "refunded", "cancelled", "canceled", "error", "disabled", "deleted": .negative
        case "pending", "requested", "awaiting_s2s": .warning
        default: .secondary
        }
    }
}

extension Font {
    /// Scalable, rounded display face for the signature figures (today's gross
    /// volume, etc.). Built on a Dynamic Type text style — replaces the fixed
    /// 44pt/30pt sizes that ignored accessibility text sizing.
    static func display(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, design: .rounded).weight(.bold)
    }
}

// MARK: - Shared chrome components

/// A small capsule chip. One component for every badge in the app.
/// `systemImage` lets meaning ride on a glyph, not just the tint.
struct Badge: View {
    let text: String
    var color: Color = .secondary
    var systemImage: String? = nil
    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let systemImage { Image(systemName: systemImage) }
        }
        .labelStyle(.titleAndIcon)
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, Spacing.sm).padding(.vertical, 3)
        .background(color.opacity(0.18), in: Capsule())
        .foregroundStyle(color)
    }
}

/// Capsule for a backend status — colored via `StatusStyle` and announced to
/// VoiceOver as "Status: …" so the meaning isn't color-only.
struct StatusBadge: View {
    let status: String
    var body: some View {
        Badge(text: status.capitalized, color: StatusStyle.color(status))
            .accessibilityElement()
            .accessibilityLabel("Status: \(status.capitalized)")
    }
}

/// A signed percentage delta. The arrow makes direction legible without color,
/// and the VoiceOver label speaks "up/down N percent".
struct TrendDelta: View {
    let percent: Decimal?
    var font: Font = .subheadline.weight(.semibold)
    var pill: Bool = false
    var body: some View {
        if let percent {
            let up = percent >= 0
            let str = percent.formatted(.number.precision(.fractionLength(1)))
            let tint: Color = up ? .positive : .negative
            Label("\(up ? "+" : "")\(str)%", systemImage: up ? "arrow.up.right" : "arrow.down.right")
                .labelStyle(.titleAndIcon)
                .font(font)
                .monospacedDigit()
                .foregroundStyle(tint)
                .modifier(DeltaPillBackground(tint: tint, on: pill))
                .accessibilityElement()
                .accessibilityLabel("\(up ? "Up" : "Down") \(str) percent")
        }
    }
}

private struct DeltaPillBackground: ViewModifier {
    let tint: Color
    let on: Bool
    func body(content: Content) -> some View {
        if on {
            content.padding(.horizontal, 10).padding(.vertical, 5)
                .background(tint.opacity(0.16), in: Capsule())
        } else { content }
    }
}

// MARK: - Loading skeleton

/// A redacted placeholder block — use instead of a bare spinner so layout
/// doesn't jump when content arrives. Honours Reduce Motion (no shimmer).
struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var body: some View {
        RoundedRectangle(cornerRadius: Radius.tooltip, style: .continuous)
            .fill(.quaternary)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .accessibilityHidden(true)
    }
}

// MARK: - Focused refresh action (⌘R)

/// Each screen publishes its reload closure here so the app-level ⌘R command can
/// refresh whatever is focused without threading callbacks through the shell.
struct RefreshActionKey: FocusedValueKey { typealias Value = @MainActor () -> Void }
extension FocusedValues {
    var refreshAction: RefreshActionKey.Value? {
        get { self[RefreshActionKey.self] }
        set { self[RefreshActionKey.self] = newValue }
    }
}

extension View {
    /// Registers a refresh action for the ⌘R menu command while this view is focused.
    func refreshCommand(_ action: @escaping @MainActor () -> Void) -> some View {
        focusedSceneValue(\.refreshAction, action)
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
///
/// The prior load is cancelled before a new one starts, so a rapid switch
/// (tenant → tenant, date range → date range) can't resolve newest-loses: every
/// `load()` swallows `CancellationError`, so cancel-and-replace is deterministic
/// newest-wins rather than a coin-flip on which response returns last.
private struct ReloadTrigger<ID: Equatable>: ViewModifier {
    let id: ID
    let action: () async -> Void
    @State private var loadedID: ID?
    @State private var task: Task<Void, Never>?
    func body(content: Content) -> some View {
        content
            .onAppear { if loadedID != id { loadedID = id; start() } }
            .onChange(of: id) { _, newID in loadedID = newID; start() }
    }
    private func start() {
        task?.cancel()
        task = Task { await action() }
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

/// Shared auto-refresh clock: the visible screen's refresh loop publishes the next
/// fire time here so the toolbar can count down to it, and "Refresh now" bumps
/// `manualTick` to restart the loop (which resets the countdown).
@Observable final class AutoRefreshState {
    var nextFireAt: Date?
    private(set) var manualTick = 0
    func refreshNow() { manualTick += 1 }
}

private struct AutoRefreshStateKey: EnvironmentKey {
    static let defaultValue = AutoRefreshState()
}
extension EnvironmentValues {
    var autoRefreshState: AutoRefreshState {
        get { self[AutoRefreshStateKey.self] }
        set { self[AutoRefreshStateKey.self] = newValue }
    }
}

/// Toolbar control for auto-refresh: one flat menu — "Refresh now" plus the cadence
/// choices (checkmark on the active one) — whose label counts down to the next
/// refresh on the timer glyph while a cadence is set.
struct RefreshIntervalMenu: View {
    @Binding var seconds: Int
    var state: AutoRefreshState
    @FocusedValue(\.refreshAction) private var refreshAction

    var body: some View {
        Menu {
            Button("Refresh now", systemImage: "arrow.clockwise") {
                refreshAction?()
                state.refreshNow()
            }
            .disabled(refreshAction == nil)
            Section("Auto-refresh") {
                ForEach(RefreshInterval.options, id: \.self) { opt in
                    Button {
                        seconds = opt
                    } label: {
                        if opt == seconds {
                            Label(RefreshInterval.label(opt), systemImage: "checkmark")
                        } else {
                            Text(RefreshInterval.label(opt))
                        }
                    }
                }
            }
        } label: {
            label
        }
        .accessibilityLabel("Auto-refresh")
        .accessibilityValue(seconds == 0 ? "Off" : "Every \(RefreshInterval.label(seconds))")
    }

    /// Off → the timer glyph. Active → the glyph plus a live m:ss countdown to the
    /// next refresh (only ticks per-second while a cadence is set).
    @ViewBuilder private var label: some View {
        if seconds > 0 {
            // Only instantiated while a cadence is set, so its 1 Hz ticker stops at Off.
            CountdownLabel(seconds: seconds, state: state)
        } else {
            Label("Auto-refresh", systemImage: "timer")
        }
    }
}

/// Live m:ss countdown to the next auto-refresh, shown on the toolbar timer glyph.
///
/// Driven by a 1 Hz `Timer` publisher, **not** `TimelineView`: a `TimelineView`
/// schedule does not fire inside a toolbar `Menu` label on macOS (the toolbar
/// re-renders its label only when an observed value changes), so the countdown
/// would appear frozen. `onReceive` of a Timer publisher does fire there, and the
/// `@State` write re-renders the label each second.
private struct CountdownLabel: View {
    let seconds: Int
    let state: AutoRefreshState
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let target = state.nextFireAt ?? now.addingTimeInterval(Double(seconds))
        let remaining = max(0, Int(target.timeIntervalSince(now).rounded(.up)))
        Label(String(format: "%d:%02d", remaining / 60, remaining % 60),
              systemImage: "timer.circle.fill")
            .monospacedDigit()
            .onReceive(ticker) { now = $0 }
    }
}

private struct AutoRefreshTaskID: Equatable { let seconds: Int; let tick: Int }

private struct AutoRefresh: ViewModifier {
    @AppStorage("autoRefreshSeconds") private var seconds = 0
    @Environment(\.autoRefreshState) private var state
    let action: () async -> Void
    func body(content: Content) -> some View {
        content
            .task(id: AutoRefreshTaskID(seconds: seconds, tick: state.manualTick)) {
                guard seconds > 0 else { state.nextFireAt = nil; return }
                while !Task.isCancelled {
                    state.nextFireAt = Date().addingTimeInterval(Double(seconds))
                    try? await Task.sleep(for: .seconds(Double(seconds)))
                    if Task.isCancelled { break }
                    await action()
                }
            }
    }
}

extension View {
    /// Runs `action` on the shared auto-refresh cadence (no-op while set to Off),
    /// publishing the next fire time to `AutoRefreshState` for the toolbar countdown.
    /// The cadence control lives in the shell toolbar (`RefreshIntervalMenu`).
    func autoRefresh(_ action: @escaping () async -> Void) -> some View {
        modifier(AutoRefresh(action: action))
    }
}
