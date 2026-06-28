import SwiftUI
import EsimplifiedKit

struct OrdersScreen: View {
    let session: Session
    var tenant: String?

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.tokenProvider) private var tokenProvider
    @State private var phase: Phase = .loading
    @State private var orders: [Order] = []
    @State private var total = 0
    @State private var search = ""
    @State private var path = NavigationPath()
    @State private var offset = 0
    @State private var filters = OrderHistoryFilterSelection()
    @State private var orderFiltersEnabled = false
    @State private var showOrderFilters = false
    /// Persisted across launches — change it once and it sticks.
    @AppStorage("ordersPageSize") private var pageSize = 25

    enum Phase { case loading, loaded, failed(String) }

    private var isFiltering: Bool { !search.isEmpty || !filters.isEmpty }

    private static let pageSizes = [25, 50, 100, 200]
    private var totalPages: Int { total == 0 ? 1 : (total + pageSize - 1) / pageSize }

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
                        HStack(spacing: Spacing.md) {
                            OrdersCountHeader(total: total, filtering: isFiltering)
                            #if os(macOS)
                            Spacer()
                            pageSizeMenu
                            rangeText
                            pageButtons
                            #endif
                        }
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.sm)
                        Divider()
                        if orders.isEmpty {
                            ScrollView {
                                ContentUnavailableView("No matching orders", systemImage: "tray")
                                    .frame(maxWidth: .infinity, minHeight: 280)
                            }
                            .frame(maxHeight: .infinity)
                            .scrollBounceBehavior(.always, axes: .vertical)
                            .refreshable { await load() }
                        } else if useTable {
                            RefreshableOrdersTable(orders: orders, onRefresh: load) { path.append($0) }
                                .frame(maxHeight: .infinity)
                        } else {
                            List(orders) { order in
                                Group {
                                    if let ref = order.customerRef {
                                        Button { path.append(ref) } label: { OrderRow(order: order) }
                                            .buttonStyle(.plain)
                                    } else {
                                        OrderRow(order: order)
                                    }
                                }
                                .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.lg,
                                                          bottom: Spacing.xs, trailing: Spacing.lg))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                            .refreshable { await load() }
                        }
                        #if !os(macOS)
                        Divider()
                        paginationBar
                        #endif
                    }
                }
            }
            .navigationTitle("Order History")
            .navigationDestination(for: CustomerRef.self) { CustomerDetailScreen(session: session, ref: $0) }
            .background(AppBackground())
            .refreshCommand { Task { await load() } }
        }
        .toolbar {
            if orderFiltersEnabled {
                ToolbarItem {
                    AdminFilterToolbarButton(activeCount: filters.activeCount) {
                        showOrderFilters = true
                    }
                }
            }
        }
        .adminFilterPresentation(isPresented: $showOrderFilters, usePopover: useTable) {
            OrderHistoryFilterPanel(selection: $filters)
        }
        .searchable(text: $search, prompt: "Package, customer, email, order #")
        // Server-side search (the web searches server-side; a local filter would only
        // see the rows already loaded and silently miss matches beyond the page).
        .debouncedSearch(of: search) { offset = 0; await load() }
        .reload(on: tenant) { offset = 0; await load() }
        .refreshCommand { Task { await load() } }
        .onChange(of: pageSize) { offset = 0; Task { await load() } }
        .onChange(of: filters) { offset = 0; Task { await load() } }
        .task { await refreshFilterPermission() }
    }

    /// Mirrors the web: Payment Method / Payment Status / Order Type filters are
    /// superuser-only (we also allow staff as a stand-in for the web's Admin group).
    private func refreshFilterPermission() async {
        do {
            let client = LiveAPIClient(host: session.host, tokenProvider: tokenProvider)
            let user = try await client.get("/api/me/", query: [:], as: MeUser.self)
            orderFiltersEnabled = user.isSuperuser || user.isStaff
        } catch {
            orderFiltersEnabled = false
        }
    }

    private func load() async {
        if orders.isEmpty { phase = .loading }
        do {
            let client = LiveAPIClient(host: session.host, tokenProvider: tokenProvider)
            let path = tenant.map { "/api/orders/\($0)/" } ?? "/api/orders/"
            var query = ["limit": "\(pageSize)", "offset": "\(offset)"]
            query.merge(filters.queryParams()) { _, new in new }
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

    private var pageSizeMenu: some View {
        Menu {
            Picker("Page size", selection: $pageSize) {
                ForEach(Self.pageSizes, id: \.self) { Text("\($0) per page").tag($0) }
            }
        } label: { Label("\(pageSize) / page", systemImage: "list.number") }
    }

    @ViewBuilder private var rangeText: some View {
        if total > 0 {
            Text("\(offset + 1)–\(min(offset + orders.count, total)) of \(total.formatted())")
                .foregroundStyle(.secondary).monospacedDigit()
        }
    }

    @ViewBuilder private var pageButtons: some View {
        if totalPages > 1 {
            Button { Task { await go(to: offset - pageSize) } } label: { Image(systemName: "chevron.left") }
                .disabled(offset == 0).accessibilityLabel("Previous page")
            Button { Task { await go(to: offset + pageSize) } } label: { Image(systemName: "chevron.right") }
                .disabled(offset + pageSize >= total).accessibilityLabel("Next page")
        }
    }

    #if !os(macOS)
    /// iPhone/iPad bottom pagination bar. macOS shows the same controls in the
    /// header row instead, so they clear the global bottom status bar.
    private var paginationBar: some View {
        HStack(spacing: Spacing.md) {
            pageSizeMenu
            Spacer()
            rangeText
            pageButtons
        }
        .font(.caption)
        .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.sm)
    }
    #endif

    /// Clamp to a valid page start, then reload.
    private func go(to newOffset: Int) async {
        offset = max(0, min(newOffset, (totalPages - 1) * pageSize))
        await load()
    }
}

// MARK: - Order history filters (mirrors web FilterBar on /admin/order-history)

enum OrderHistoryFilterCategory: CaseIterable, Identifiable {
    case paymentMethod, paymentStatus, orderType

    var id: String { queryKey }

    var name: String {
        switch self {
        case .paymentMethod: "Payment Method"
        case .paymentStatus: "Payment Status"
        case .orderType: "Order Type"
        }
    }

    var queryKey: String {
        switch self {
        case .paymentMethod: "payment_method"
        case .paymentStatus: "payment_status"
        case .orderType: "order_type"
        }
    }

    /// Display label + API value (web `toKey`: lowercase, spaces → underscores).
    var options: [(label: String, value: String)] {
        switch self {
        case .paymentMethod:
            [
                ("Complimentary", "complimentary"),
                ("Stripe Checkout", "stripe_checkout"),
                ("Stripe Intent", "stripe_intent"),
                ("Agent Payment", "agent_payment"),
                ("Voucher", "voucher"),
            ]
        case .paymentStatus:
            [
                ("Refunded", "refunded"),
                ("Pending", "pending"),
                ("Success", "success"),
            ]
        case .orderType:
            [
                ("Buy", "buy"),
                ("Top Up", "top_up"),
                ("Auto Top Up", "auto_top_up"),
                ("Add Plan", "add_plan"),
            ]
        }
    }
}

struct OrderHistoryFilterSelection: Equatable {
    private var values: [String: Set<String>] = [:]

    func selected(for category: OrderHistoryFilterCategory) -> Set<String> {
        values[category.queryKey] ?? []
    }

    mutating func setSelected(_ set: Set<String>, for category: OrderHistoryFilterCategory) {
        if set.isEmpty {
            values.removeValue(forKey: category.queryKey)
        } else {
            values[category.queryKey] = set
        }
    }

    mutating func clear(category: OrderHistoryFilterCategory) {
        setSelected([], for: category)
    }

    mutating func clearAll() { values = [:] }

    var isEmpty: Bool { values.isEmpty }

    var activeCount: Int {
        OrderHistoryFilterCategory.allCases.reduce(0) { $0 + selected(for: $1).count }
    }

    func queryParams() -> [String: String] {
        var params: [String: String] = [:]
        for cat in OrderHistoryFilterCategory.allCases {
            let sel = selected(for: cat)
            if !sel.isEmpty {
                params[cat.queryKey] = sel.sorted().joined(separator: ",")
            }
        }
        return params
    }

}

/// Grouped toggles for Order History — shown in a sheet (iPhone) or popover (Mac/iPad).
private struct OrderHistoryFilterPanel: View {
    @Binding var selection: OrderHistoryFilterSelection

    var body: some View {
        List {
            ForEach(OrderHistoryFilterCategory.allCases) { cat in
                Section(cat.name) {
                    ForEach(cat.options, id: \.value) { opt in
                        Toggle(opt.label, isOn: toggleBinding(cat, opt.value))
                    }
                }
            }
            if !selection.isEmpty {
                Section {
                    Button("Clear all", role: .destructive) { selection.clearAll() }
                }
            }
        }
        #if os(macOS)
        .frame(width: 320, height: 440)
        #else
        .frame(minHeight: 360)
        #endif
    }

    private func toggleBinding(_ cat: OrderHistoryFilterCategory, _ value: String) -> Binding<Bool> {
        Binding(
            get: { selection.selected(for: cat).contains(value) },
            set: { on in
                var next = selection
                var set = next.selected(for: cat)
                if on { set.insert(value) } else { set.remove(value) }
                next.setSelected(set, for: cat)
                selection = next
            }
        )
    }
}

private struct OrdersCountHeader: View {
    let total: Int
    let filtering: Bool
    var body: some View {
        HStack(spacing: 6) {
            Text("\(total.formatted())").font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
            Text((filtering ? "matching " : "") + (total == 1 ? "order" : "orders"))
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

/// Category word for VoiceOver only — visual distinction is `orderAccent` tint.
private func orderCategoryWord(_ order: Order) -> String? {
    if order.paymentStatus.lowercased() == "refunded" { return "Refunded" }
    if order.isComplimentary { return "Complimentary" }
    switch order.paymentMethod {
    case "agent_payment": return "Agent"
    case "voucher": return "Voucher"
    default: break
    }
    if order.discountCode != nil && order.paymentStatus.lowercased() == "success" { return "Promo" }
    return nil
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

/// `Table` on Mac/iPad hosts an AppKit scroll view, so `.refreshable` on the table
/// itself never fires. Size the table to its full row height inside a bouncing
/// `ScrollView` — same pattern as `DashboardScreen`.
private struct RefreshableOrdersTable: View {
    let orders: [Order]
    var onRefresh: () async -> Void
    var onOpen: (CustomerRef) -> Void

    private static let rowHeight: CGFloat = 48
    private static let headerHeight: CGFloat = 28

    private var contentHeight: CGFloat {
        CGFloat(max(orders.count, 1)) * Self.rowHeight + Self.headerHeight
    }

    var body: some View {
        ScrollView {
            OrdersTable(orders: orders, onOpen: onOpen)
                .frame(height: contentHeight)
                .scrollDisabled(true)
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        .refreshable { await onRefresh() }
    }
}

/// Columnar table for Mac/iPad — mirrors the web's Order History columns.
/// The whole row is clickable (selection → `onOpen`), like a native table.
/// Columns are click-to-sort (client-side over the loaded page) and drag-to-reorder
/// (persisted via `TableColumnCustomization`).
private struct OrdersTable: View {
    let orders: [Order]
    var onOpen: (CustomerRef) -> Void
    @State private var selectedID: Order.ID?
    @State private var sortOrder: [KeyPathComparator<Order>] = [
        KeyPathComparator(\Order.purchaseDate, order: .reverse)
    ]
    @AppStorage("ordersTableColumnCustomization")
    private var columnCustomization = TableColumnCustomization<Order>()

    /// Stable IDs for column reordering — must be compile-time literals, not localized.
    private enum ColumnID {
        static let tenant = "tenant"
        static let package = "package"
        static let customer = "customer"
        static let purchasedIn = "purchasedIn"
        static let type = "type"
        static let price = "price"
        static let local = "local"
        static let discount = "discount"
        static let status = "status"
        static let date = "date"
    }

    /// The loaded page, re-sorted by the active column. Search/pagination are
    /// unchanged — this only reorders the rows already on screen.
    private var shown: [Order] { orders.sorted(using: sortOrder) }

    var body: some View {
        Table(shown, selection: $selectedID, sortOrder: $sortOrder,
              columnCustomization: $columnCustomization) {
            TableColumn("Tenant", value: \.tenant) { o in
                HStack(spacing: Spacing.sm) {
                    TenantAvatar(tenant: o.tenant, size: 22)
                    Text(o.tenant).foregroundStyle(orderAccent(o) ?? .primary).lineLimit(1)
                }
            }
            .customizationID(ColumnID.tenant)
            TableColumn("Package", value: \.packageName) { o in
                Text(o.packageName).foregroundStyle(orderAccent(o) ?? .primary).lineLimit(1)
            }
            .customizationID(ColumnID.package)
            TableColumn("Customer") { o in customerCell(o) }
                .customizationID(ColumnID.customer)
            TableColumn("Purchased In") { o in
                Text(o.purchaseCountry ?? "—").foregroundStyle(.secondary)
            }
            .customizationID(ColumnID.purchasedIn)
            TableColumn("Type", value: \.orderType) { o in Text(o.orderType).foregroundStyle(.secondary) }
                .customizationID(ColumnID.type)
            TableColumn("Price", value: \.finalPrice) { o in Text(o.usdPriceDisplay).monospacedDigit() }
                .customizationID(ColumnID.price)
            TableColumn("Local") { o in
                Text(o.localPriceDisplay ?? "").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            .customizationID(ColumnID.local)
            TableColumn("Discount") { o in
                if let code = o.discountCode { Text(code).foregroundStyle(.orange) } else { Text("") }
            }
            .customizationID(ColumnID.discount)
            TableColumn("Status", value: \.paymentStatus) { o in
                Text(o.paymentStatus.capitalized)
                    .foregroundStyle(StatusStyle.color(o.paymentStatus))
            }
                .customizationID(ColumnID.status)
            TableColumn("Date", value: \.purchaseDate) { o in
                Text(shortDate(o.purchaseDate)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            .customizationID(ColumnID.date)
        }
        .scrollContentBackground(.hidden)   // let the app gradient show instead of the Table's opaque black
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

/// iPhone order row — a transaction-ledger cell (à la Wallet): the tenant's logo
/// leads (glass tile, monogram fallback), a three-tier hierarchy reads package /
/// status·date / customer, and prices sit right-aligned and monospaced. The tinted
/// title still encodes category (promo/voucher) without a separate tag.
private struct OrderRow: View {
    let order: Order

    private var accent: Color? { orderAccent(order) }
    private var title: String { order.packageName.isEmpty ? order.orderNumber : order.packageName }
    private var showsChevron: Bool { order.customerRef != nil }

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            TenantAvatar(tenant: order.tenant)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline).foregroundStyle(accent ?? .primary).lineLimit(1)
                Text(detailLine)
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if let who = subtitle {
                    Text(who).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: Spacing.sm)
            VStack(alignment: .trailing, spacing: 3) {
                Text(order.usdPriceDisplay).font(.headline.monospacedDigit())
                if let local = order.localPriceDisplay {
                    Text(local).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    .padding(.leading, 2)
            }
        }
        .padding(.vertical, Spacing.md).padding(.horizontal, Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .contentShape(.rect(cornerRadius: Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Second line — a non-success status (so refunds/pending aren't color-only) and
    /// the date. The tenant is the leading logo, so it isn't repeated here.
    private var detailLine: String {
        var parts: [String] = []
        let s = order.paymentStatus.lowercased()
        if !(s == "success" || s == "approved" || s == "active" || s == "released") {
            parts.append(order.paymentStatus.capitalized)
        }
        parts.append(shortDate(order.purchaseDate))
        return parts.joined(separator: " · ")
    }

    /// One spoken summary for the whole row, in reading order: what was bought,
    /// its status + category, the USD price, the tenant, when, and for whom.
    private var accessibilityLabel: String {
        var parts: [String] = [title, "Status \(order.paymentStatus.capitalized)"]
        if let cat = orderCategoryWord(order) { parts.append(cat) }
        parts.append("\(order.usdPriceDisplay) USD")
        if let t = tenantName { parts.append(t) }
        parts.append(shortDate(order.purchaseDate))
        if let who = subtitle { parts.append(who) }
        return parts.joined(separator: ", ")
    }

    /// Third line — the people tier: who bought it and from where.
    private var subtitle: String? {
        let who = order.customerName ?? order.customerEmail
        let parts = [who, order.purchaseCountry].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    private var tenantName: String? { order.tenant.isEmpty ? nil : order.tenant }
}

/// The tenant's brand logo filled into a rounded glass tile (the app's Liquid Glass),
/// with a monogram fallback (initial in a stable per-tenant tint) for tenants with no
/// logo on file. Size-configurable so the iPhone row and the Mac table share it.
struct TenantAvatar: View {
    let tenant: String
    var size: CGFloat = 38
    @Environment(\.tenantLogos) private var logos

    private var radius: CGFloat { size * 0.26 }

    var body: some View {
        content
            .frame(width: size, height: size)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
            .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        if let url = logos[tenant.lowercased()] {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    monogram   // loading or failed → monogram
                }
            }
        } else {
            monogram
        }
    }

    private var monogram: some View {
        Text(Self.initials(tenant))
            .font(.system(size: size * 0.37, weight: .bold, design: .rounded))
            .foregroundStyle(Self.tint(tenant))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// First letters of the first two words, else the first letter (uppercased).
    private static func initials(_ s: String) -> String {
        let words = s.split { " -_".contains($0) }.filter { !$0.isEmpty }
        guard let first = words.first?.first else { return "?" }
        if words.count >= 2, let second = words[1].first {
            return (String(first) + String(second)).uppercased()
        }
        return String(first).uppercased()
    }

    /// A stable tint per tenant so the same brand always gets the same monogram color.
    private static func tint(_ s: String) -> Color {
        let palette: [Color] = [.blue, .teal, .indigo, .purple, .pink, .orange, .green, .cyan, .mint]
        let h = s.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[h % max(palette.count, 1)]
    }
}

// adminErrorMessage / shortDate / Fmt / dbl now live in AdminTheme.swift — shared
// app-wide formatting helpers, no longer parked inside a screen file.
