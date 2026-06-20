import SwiftUI
import EsimplifiedKit

struct OrdersScreen: View {
    let session: Session
    var tenant: String?

    @Environment(\.horizontalSizeClass) private var hSize
    @State private var phase: Phase = .loading
    @State private var orders: [Order] = []
    @State private var total = 0
    @State private var search = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var path = NavigationPath()

    enum Phase { case loading, loaded, failed(String) }

    /// iPhone (compact) gets rich rows; Mac/iPad (regular) gets a columnar table.
    private var useTable: Bool { hSize != .compact }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch phase {
                case .loading where orders.isEmpty:
                    OrdersLoadingPlaceholder()
                case let .failed(message) where orders.isEmpty:
                    ContentUnavailableView {
                        Label("Couldn't load orders", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") { Task { await load() } }
                            .buttonStyle(.glassProminent)
                    }
                default:
                    VStack(spacing: 0) {
                        OrdersCountHeader(showing: orders.count, total: total, filtering: !search.isEmpty)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.sm)
                        Divider()
                        if orders.isEmpty {
                            ContentUnavailableView("No matching orders", systemImage: "tray")
                                .frame(maxHeight: .infinity)
                        } else if useTable {
                            OrdersTable(orders: orders) { path.append($0) }
                        } else {
                            List(orders) { order in
                                if let ref = order.customerRef {
                                    NavigationLink(value: ref) { OrderRow(order: order) }
                                } else {
                                    OrderRow(order: order)
                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                        }
                    }
                }
            }
            .navigationTitle("Order History")
            .navigationDestination(for: CustomerRef.self) { CustomerDetailScreen(session: session, ref: $0) }
            .background(AppBackground())
            .refreshCommand { Task { await load() } }
        }
        .searchable(text: $search, prompt: "Package, customer, email, order #")
        .onChange(of: search) { _, _ in debouncedSearch() }
        .reload(on: tenant) { await load() }
        .refreshable { await load() }
        .autoRefresh { await load() }
    }

    /// Debounce keystrokes, then reload from the server so search spans the whole
    /// dataset — the web searches server-side; a local filter would only see the
    /// rows already loaded (and silently miss matches beyond the page).
    private func debouncedSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            await load()
        }
    }

    private func load() async {
        if orders.isEmpty { phase = .loading }
        do {
            let client = LiveAPIClient(host: session.host, accessToken: session.accessToken)
            let path = tenant.map { "/api/orders/\($0)/" } ?? "/api/orders/"
            var query = ["limit": "500"]
            let term = search.trimmingCharacters(in: .whitespaces)
            if !term.isEmpty { query["search"] = term }
            let page = try await client.get(path, query: query, as: OrdersPage.self)
            orders = page.orders
            total = page.count
            phase = .loaded
        } catch let error as APIError {
            phase = .failed(adminErrorMessage(error))
        } catch is CancellationError {
            // View navigated away mid-load — not a real error.
        } catch {
            phase = .failed("Unexpected error.")
        }
    }
}

private struct OrdersCountHeader: View {
    let showing: Int
    let total: Int
    let filtering: Bool
    var body: some View {
        HStack(spacing: 6) {
            if filtering {
                Text("\(showing.formatted()) of \(total.formatted())")
            } else {
                Text("\(total.formatted())").font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                Text(total == 1 ? "order" : "orders")
            }
        }
        .font(.subheadline).foregroundStyle(.secondary)
        .textCase(nil).padding(.vertical, 2)
    }
}

/// The web's row colour language (refunded red, complimentary green, agent
/// purple, voucher cyan, discounted-success orange), shared by the row and table.
func orderAccent(_ order: Order) -> Color? {
    if order.paymentStatus.lowercased() == "refunded" { return .red }
    switch order.paymentMethod {
    case "complimentary": return .green
    case "agent_payment": return .purple
    case "voucher": return .cyan
    default: break
    }
    if order.discountCode != nil && order.paymentStatus.lowercased() == "success" { return .orange }
    return nil
}

/// A non-color signal for the order's category. Colour alone (`orderAccent`) is
/// invisible to color-blind users and VoiceOver, so we pair the tint with a glyph
/// + word: Refunded / Agent / Voucher / Comp / Promo. Returns nil for plain
/// card-paid orders (no badge needed).
struct OrderCategory {
    let word: String
    let glyph: String
    let color: Color

    init?(_ order: Order) {
        if order.paymentStatus.lowercased() == "refunded" {
            self = OrderCategory(word: "Refunded", glyph: "arrow.uturn.backward", color: .red); return
        }
        switch order.paymentMethod {
        case "complimentary": self = OrderCategory(word: "Comp", glyph: "gift.fill", color: .green); return
        case "agent_payment": self = OrderCategory(word: "Agent", glyph: "person.fill", color: .purple); return
        case "voucher": self = OrderCategory(word: "Voucher", glyph: "ticket.fill", color: .cyan); return
        default: break
        }
        if order.discountCode != nil && order.paymentStatus.lowercased() == "success" {
            self = OrderCategory(word: "Promo", glyph: "tag.fill", color: .orange); return
        }
        return nil
    }

    private init(word: String, glyph: String, color: Color) {
        self.word = word; self.glyph = glyph; self.color = color
    }
}

/// The category Badge with a VoiceOver label — the non-color reinforcement for
/// `orderAccent`, used in both the iPhone row and the Mac table.
private struct OrderCategoryBadge: View {
    let order: Order
    var body: some View {
        if let cat = OrderCategory(order) {
            Badge(text: cat.word, color: cat.color, systemImage: cat.glyph)
                .accessibilityElement()
                .accessibilityLabel("Category: \(cat.word)")
        }
    }
}

/// Skeleton placeholder shown while the first page loads — keeps layout stable
/// instead of a centred spinner that jumps when content arrives.
private struct OrdersLoadingPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            ForEach(0..<8, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        SkeletonBar(width: 180, height: 16)
                        Spacer()
                        SkeletonBar(width: 60, height: 16)
                    }
                    SkeletonBar(width: 240, height: 11)
                }
            }
            Spacer()
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement()
        .accessibilityLabel("Loading orders")
    }
}

/// Cross-platform clipboard copy for the table's context menu.
private func copyToClipboard(_ string: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
    #else
    UIPasteboard.general.string = string
    #endif
}

/// Columnar table for Mac/iPad — mirrors the web's Order History columns.
/// The whole row is clickable (selection → `onOpen`), like a native table.
/// Columns are click-to-sort; sorting is client-side over the loaded page.
private struct OrdersTable: View {
    let orders: [Order]
    var onOpen: (CustomerRef) -> Void
    @State private var selectedID: Order.ID?
    @State private var sortOrder: [KeyPathComparator<Order>] = [
        KeyPathComparator(\Order.purchaseDate, order: .reverse)
    ]

    /// The loaded page, re-sorted by the active column. Search/pagination are
    /// unchanged — this only reorders the rows already on screen.
    private var shown: [Order] { orders.sorted(using: sortOrder) }

    var body: some View {
        Table(shown, selection: $selectedID, sortOrder: $sortOrder) {
            TableColumn("Tenant", value: \.tenant) { o in
                Text(o.tenant).foregroundStyle(orderAccent(o) ?? .primary)
            }
            TableColumn("Package", value: \.packageName) { o in
                HStack(spacing: Spacing.sm) {
                    Text(o.packageName).foregroundStyle(orderAccent(o) ?? .primary).lineLimit(1)
                    OrderCategoryBadge(order: o)
                }
            }
            TableColumn("Customer") { o in customerCell(o) }
            TableColumn("Purchased In") { o in
                Text(o.purchaseCountry ?? "—").foregroundStyle(.secondary)
            }
            TableColumn("Type", value: \.orderType) { o in Text(o.orderType).foregroundStyle(.secondary) }
            TableColumn("Price", value: \.finalPrice) { o in Text(o.usdPriceDisplay).monospacedDigit() }
            TableColumn("Local") { o in
                Text(o.localPriceDisplay ?? "").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            TableColumn("Discount") { o in
                if let code = o.discountCode { Text(code).foregroundStyle(.orange) } else { Text("") }
            }
            TableColumn("Status", value: \.paymentStatus) { o in StatusBadge(status: o.paymentStatus) }
            TableColumn("Date", value: \.purchaseDate) { o in
                Text(shortDate(o.purchaseDate)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .contextMenu(forSelectionType: Order.ID.self) { ids in
            if let id = ids.first, let o = shown.first(where: { $0.id == id }) {
                if let ref = o.customerRef {
                    Button("Open Customer", systemImage: "person.crop.circle") { onOpen(ref) }
                }
                if let iccid = o.iccid, !iccid.isEmpty {
                    Button("Copy ICCID", systemImage: "doc.on.doc") { copyToClipboard(iccid) }
                }
                Button("Copy order number", systemImage: "number") { copyToClipboard(o.orderNumber) }
            }
        }
        .onChange(of: selectedID) { _, id in
            guard let id, let o = shown.first(where: { $0.id == id }), let ref = o.customerRef else { return }
            onOpen(ref)
            selectedID = nil
        }
    }

    @ViewBuilder private func customerCell(_ o: Order) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let n = o.customerName, !n.isEmpty { Text(n).lineLimit(1) }
            if let e = o.customerEmail, !e.isEmpty {
                Text(e).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

private struct OrderRow: View {
    let order: Order

    private var accent: Color? { orderAccent(order) }
    private var title: String { order.packageName.isEmpty ? order.orderNumber : order.packageName }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline).foregroundStyle(accent ?? .primary).lineLimit(1)
                Spacer(minLength: Spacing.sm)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(order.usdPriceDisplay).font(.headline.monospacedDigit())
                    if let local = order.localPriceDisplay {
                        Text(local).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: Spacing.sm) {
                StatusBadge(status: order.paymentStatus)
                OrderCategoryBadge(order: order)
                if !order.orderType.isEmpty {
                    Badge(text: order.orderType)
                }
                if let code = order.discountCode {
                    Badge(text: code, color: .orange, systemImage: "tag.fill")
                }
                Spacer(minLength: Spacing.sm)
                Text(shortDate(order.purchaseDate)).font(.caption2).foregroundStyle(.secondary)
            }
            if let who = subtitle {
                Text(who).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// One spoken summary for the whole row, in reading order: what was bought,
    /// its status + category, the USD price, when, and for whom.
    private var accessibilityLabel: String {
        var parts: [String] = [title, "Status \(order.paymentStatus.capitalized)"]
        if let cat = OrderCategory(order) { parts.append(cat.word) }
        parts.append("\(order.usdPriceDisplay) USD")
        parts.append(shortDate(order.purchaseDate))
        if let who = subtitle { parts.append(who) }
        return parts.joined(separator: ", ")
    }

    private var subtitle: String? {
        let who = order.customerName ?? order.customerEmail
        let parts = [who, order.purchaseCountry, tenantName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    private var tenantName: String? { order.tenant.isEmpty ? nil : order.tenant }
}

/// Shared mapping from an APIError to a user-facing message (used by admin screens).
func adminErrorMessage(_ error: APIError) -> String {
    switch error {
    case .unreachable: "Couldn't reach the server."
    case .authExpired: "Your session expired — sign in again."
    case .notFound: "Not found."
    case let .server(code): "Server error (\(code))."
    case let .requestFailed(code, message): message.map { "Server (\(code)): \($0)" } ?? "Request failed (\(code))."
    case .decoding: "Couldn't read the server response."
    }
}

func shortDate(_ iso: String) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    guard let date else { return String(iso.prefix(10)) }
    return date.formatted(date: .abbreviated, time: .shortened)
}
