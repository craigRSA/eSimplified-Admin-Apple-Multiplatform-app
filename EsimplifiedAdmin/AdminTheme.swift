import SwiftUI
import Combine
import EsimplifiedKit

// MARK: - Shared formatting & error helpers

/// Maps an `APIError` to a user-facing message — shared by every admin screen.
func adminErrorMessage(_ error: APIError) -> String {
    switch error {
    case .unreachable: "Couldn't reach the server."
    case .authExpired: "Your session expired — sign in again."
    case .notFound: "Not found."
    case let .requestFailed(code, message): message.map { "Server (\(code)): \($0)" } ?? "Request failed (\(code))."
    case .decoding: "Couldn't read the server response."
    }
}

/// Parses an ISO-8601 timestamp (with or without fractional seconds) to a short
/// local date-time, falling back to the date prefix if it can't parse.
func shortDate(_ iso: String) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    guard let date else { return String(iso.prefix(10)) }
    return date.formatted(date: .abbreviated, time: .shortened)
}

/// Decimal → Double, for the (Double-based) Charts API and the money formatter.
func dbl(_ d: Decimal) -> Double { (d as NSDecimalNumber).doubleValue }

/// App-wide money / count formatting.
enum Fmt {
    /// How a money figure should read — chosen per card/metric, not inferred from size.
    enum MoneyStyle {
        /// Revenue totals and aggregates ($3,900, $152,340).
        case whole
        /// Per-order averages ($12.34).
        case cents
    }

    static func money(_ d: Decimal, style: MoneyStyle) -> String {
        if d == 0 { return "$0" }
        let cents = style == .cents
        return "$" + d.formatted(.number.precision(.fractionLength(cents ? 2 : 0)).grouping(.automatic))
    }
    /// Abbreviated for the macOS menu-bar label only.
    static func moneyCompact(_ d: Decimal) -> String {
        let v = abs(dbl(d))
        if v >= 1000 {
            return "$" + v.formatted(.number.notation(.compactName).precision(.fractionLength(1)))
        }
        return money(d, style: .whole)
    }
    /// Grouped whole numbers (157,234) — integer counts, never abbreviated.
    static func count(_ n: Int) -> String {
        n.formatted(.number.grouping(.automatic))
    }
}

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
            // Kept low so it reads as a brand tint behind content, not a blue glow on
            // sparse screens (e.g. the "Pick a tenant" states).
            RadialGradient(
                colors: [Color.accentColor.opacity(0.08), .clear],
                center: .top, startRadius: 0, endRadius: 460
            )
        }
        .ignoresSafeArea()
    }
}

/// A calm, centered empty state — quiet glyph, title, optional message — drawn
/// straight on the backdrop with no card or tint. Use it where the framing of a
/// `ContentUnavailableView` would read as a stray coloured box on a near-empty
/// screen (the tenant/search prompts).
struct QuietEmptyState: View {
    let title: String
    let systemImage: String
    var message: String?
    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .regular)).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.map { "\(title). \($0)" } ?? title)
    }
}

// MARK: - Toolbar filters

/// Shared filter icon — every list screen uses the same toolbar control.
enum AdminFilterIcon {
    static let systemName = "line.3.horizontal.decrease.circle"
}

/// Single-choice filter in the toolbar (Customers Active/Inactive/All, Agent Approvals, etc.).
struct AdminPickerFilter<Item: Hashable & Identifiable>: View {
    let menuTitle: String
    @Binding var selection: Item
    let options: [Item]
    let label: (Item) -> String

    var body: some View {
        Menu {
            Picker(menuTitle, selection: $selection) {
                ForEach(options) { item in
                    Text(label(item)).tag(item)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(label(selection), systemImage: AdminFilterIcon.systemName)
        }
    }
}

/// Multi-category filter toolbar button — label stays "Filter", count when active.
struct AdminFilterToolbarButton: View {
    let activeCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(activeCount > 0 ? "Filter (\(activeCount))" : "Filter")
            } icon: {
                Image(systemName: AdminFilterIcon.systemName)
            }
        }
        .accessibilityLabel(
            activeCount > 0 ? "Filter, \(activeCount) active" : "Filter"
        )
    }
}

extension View {
    /// Sheet on iPhone; popover on Mac and regular-width iPad — Mail-style filter panel.
    @ViewBuilder
    func adminFilterPresentation<Content: View>(
        isPresented: Binding<Bool>,
        usePopover: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        if usePopover {
            popover(isPresented: isPresented, arrowEdge: .top) {
                content()
            }
        } else {
            sheet(isPresented: isPresented) {
                NavigationStack {
                    content()
                        .navigationTitle("Filter")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { isPresented.wrappedValue = false }
                            }
                        }
                }
                #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #endif
            }
        }
    }
}

// MARK: - Glass card

private struct GlassCard: ViewModifier {
    let radius: CGFloat
    let padding: CGFloat
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

// MARK: - Focused search action (⌘F while already on Search)

/// SearchScreen publishes this so a second ⌘F focuses the query field in place.
struct SearchFocusActionKey: FocusedValueKey { typealias Value = @MainActor () -> Void }
extension FocusedValues {
    var searchFocusAction: SearchFocusActionKey.Value? {
        get { self[SearchFocusActionKey.self] }
        set { self[SearchFocusActionKey.self] = newValue }
    }
}

extension View {
    func searchFocusCommand(_ action: @escaping @MainActor () -> Void) -> some View {
        focusedSceneValue(\.searchFocusAction, action)
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
                Text(eyebrow.uppercased()).eyebrow()
            }
            Text(title).font(.title3.weight(.semibold))
        }
    }
}

extension Text {
    /// The app's uppercase eyebrow/overline register — caption2, semibold, tracked,
    /// secondary. One definition so every overline (this header, the dashboard
    /// Eyebrow, the menu-bar Overline, the eSIM section headers) stays in lockstep.
    func eyebrow() -> some View {
        font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(.secondary)
    }
}

/// A titled glass section — a `SectionHeader` over its content, wrapped in a glass
/// card. Shared by the dashboard cards and the customer-detail sections so every
/// titled section reads the same (one title style, one card treatment).
struct SectionCard<Content: View>: View {
    let title: String
    var eyebrow: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title, eyebrow: eyebrow)
            content
        }
        .glassCard()
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
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
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

/// Debounces `query` changes by 300ms then runs `action`, cancelling the pending
/// run on each keystroke — the server-side search debounce shared by the list
/// screens so neither re-implements the timing or the cancellable Task.
private struct DebouncedSearch: ViewModifier {
    let query: String
    let action: () async -> Void
    @State private var task: Task<Void, Never>?
    func body(content: Content) -> some View {
        content.onChange(of: query) { _, _ in
            task?.cancel()
            task = Task {
                try? await Task.sleep(for: .milliseconds(300))
                if Task.isCancelled { return }
                await action()
            }
        }
    }
}

extension View {
    /// Reloads via `action` shortly after `query` stops changing (server-side search).
    func debouncedSearch(of query: String, _ action: @escaping () async -> Void) -> some View {
        modifier(DebouncedSearch(query: query, action: action))
    }
}

// MARK: - Auto-refresh

/// Overview auto-refresh interval (seconds; 0 = off), persisted across launches.
enum RefreshInterval {
    static let options: [Int] = [0, 15, 30, 60, 300]
    static func label(_ s: Int) -> String {
        switch s {
        case 0: "Off"
        case 15: "15 sec"
        case 30: "30 sec"
        case 60: "1 min"
        case 300: "5 min"
        default: "\(s) sec"
        }
    }
}

/// Toolbar control for Overview auto-refresh: one flat menu — "Refresh now" plus the
/// cadence choices (checkmark on the active one). The label shows the chosen cadence.
struct RefreshIntervalMenu: View {
    @Binding var seconds: Int
    @FocusedValue(\.refreshAction) private var refreshAction

    var body: some View {
        Menu {
            Button("Refresh now", systemImage: "arrow.clockwise") { refreshAction?() }
                .disabled(refreshAction == nil)
            Divider()
            // A Picker owns its own selection + checkmark and updates reliably inside
            // a macOS toolbar menu; hand-rolled Buttons did not reflect the choice.
            Picker("Auto-refresh", selection: $seconds) {
                ForEach(RefreshInterval.options, id: \.self) { opt in
                    Text(RefreshInterval.label(opt)).tag(opt)
                }
            }
            .pickerStyle(.inline)
        } label: {
            #if os(macOS)
            // A macOS toolbar menu label is cached by AppKit and won't animate, so keep
            // it static here — the live countdown ring lives in the status bar
            // (RefreshStatus), which re-renders reliably.
            Label("Auto-refresh", systemImage: "timer")
            #else
            if seconds > 0 {
                CountdownIcon(seconds: seconds)
            } else {
                Label("Auto-refresh", systemImage: "timer")
            }
            #endif
        }
        .accessibilityLabel("Auto-refresh")
        .accessibilityValue(seconds == 0 ? "Off" : "Every \(RefreshInterval.label(seconds))")
    }
}

/// Fraction of the current interval still to go (1 → 0 each cycle), from a
/// self-contained anchor — no coupling to the refresh loop; both run on the same
/// period and reset together when the cadence changes, so they stay in step.
private func refreshRemaining(seconds: Int, anchor: Date, now: Date) -> Double {
    let period = Double(seconds)
    guard period > 0 else { return 1 }
    let elapsed = now.timeIntervalSince(anchor).truncatingRemainder(dividingBy: period)
    return min(1, max(0, 1 - elapsed / period))
}

/// A ring that empties toward the next refresh, drawn around a small timer glyph.
private struct CountdownRing: View {
    let remaining: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 2)
            Circle().trim(from: 0, to: remaining)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "timer").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
        }
    }
}

#if os(macOS)
/// Live auto-refresh countdown for the macOS bottom status bar — a small ring that
/// empties toward the next refresh. It lives here, not the toolbar, because a macOS
/// toolbar menu label is cached by AppKit and won't animate; the status bar (like
/// its UTC clock) re-renders reliably. Its `@State` is scoped to this fixed-size
/// leaf, so only this view ticks — the container and detail screen never re-render.
struct RefreshStatus: View {
    @AppStorage("autoRefreshSeconds") private var seconds = 0
    @State private var anchor = Date()
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Always renders its content; the status bar only mounts it when a cadence is
    // set, so the ticker doesn't run while auto-refresh is Off.
    var body: some View {
        HStack(spacing: 6) {
            CountdownRing(remaining: refreshRemaining(seconds: seconds, anchor: anchor, now: now))
                .frame(width: 11, height: 11)
            Text("Auto-refresh · \(RefreshInterval.label(seconds))")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .onReceive(ticker) { now = $0 }
        .onChange(of: seconds) { anchor = Date(); now = Date() }
        .accessibilityElement()
        .accessibilityLabel("Auto-refresh every \(RefreshInterval.label(seconds))")
    }
}
#endif

#if !os(macOS)
/// iOS toolbar countdown glyph — the ring that empties toward the next refresh.
/// (macOS shows the equivalent in the status bar; its toolbar menu label is cached
/// by AppKit and won't animate.)
private struct CountdownIcon: View {
    let seconds: Int
    @State private var anchor = Date()
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        CountdownRing(remaining: refreshRemaining(seconds: seconds, anchor: anchor, now: now))
            .frame(width: 16, height: 16)
            .onReceive(ticker) { now = $0 }
            .onChange(of: seconds) { anchor = Date(); now = Date() }
            .accessibilityHidden(true)
    }
}
#endif

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
    /// Runs `action` on the Overview auto-refresh cadence (no-op while set to Off).
    /// Only `DashboardScreen` applies this; the cadence control lives in the shell
    /// toolbar (`RefreshIntervalMenu`) and is shown on Overview only.
    func autoRefresh(_ action: @escaping () async -> Void) -> some View {
        modifier(AutoRefresh(action: action))
    }
}
