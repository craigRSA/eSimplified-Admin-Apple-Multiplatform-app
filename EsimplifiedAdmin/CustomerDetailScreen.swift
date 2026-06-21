import SwiftUI
import EsimplifiedKit

/// Identifies a customer to open in `CustomerDetailScreen`. Mirrors the web's
/// customer_details route params: tenant (schema), customer_id, optional iccid.
struct CustomerRef: Hashable {
    let tenant: String
    let customerId: String
    var iccid: String?
}

extension Order {
    /// A deep-link to this order's customer, when the order carries a customer id.
    var customerRef: CustomerRef? {
        guard let cid = customerId, !cid.isEmpty else { return nil }
        return CustomerRef(tenant: tenant, customerId: cid, iccid: iccid)
    }
}

/// Native version of the web `customer_details` page: profile, the customer's
/// eSIMs, the selected eSIM's full detail (eUICC, data usage, location, package,
/// sessions), and their order history.
struct CustomerDetailScreen: View {
    let session: Session
    let ref: CustomerRef

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.tokenProvider) private var tokenProvider
    @State private var phase: Phase = .loading
    @State private var esims: [EsimSummary] = []
    @State private var orders: [Order] = []
    @State private var detailPhase: DetailPhase = .idle
    @State private var selectedIccid: String?
    @State private var customer: Customer?
    @State private var showAllOrders = false

    enum Phase { case loading, loaded, failed(String) }
    enum DetailPhase { case idle, loading, loaded(EsimDetail), failed(String) }
    @State private var sheet: EsimDetailSheet?

    private var client: LiveAPIClient { LiveAPIClient(host: session.host, tokenProvider: tokenProvider) }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView {
                    Label("Couldn't load customer", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                        .buttonStyle(.glassProminent)
                }
            case .loaded:
                content
            }
        }
        .navigationTitle(customer?.displayName ?? "Customer")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .background(AppBackground())
        .reload(on: "\(ref.customerId)|\(ref.iccid ?? "")") { await load() }
        .refreshable { await load() }
        .refreshCommand { Task { await load() } }
        .sheet(item: $sheet) { sheetContent($0) }
        .sheet(isPresented: $showAllOrders) {
            AllOrdersSheet(client: client, tenant: ref.tenant, customerId: ref.customerId)
        }
    }

    @ViewBuilder private func sheetContent(_ s: EsimDetailSheet) -> some View {
        NavigationStack {
            Group {
                switch s {
                case let .locations(iccid): LocationsSheet(session: session, iccid: iccid)
                case let .sessions(iccid): SessionsSheet(session: session, iccid: iccid)
                case let .packages(pkgs): PackagesSheet(packages: pkgs)
                case let .whitelist(items): WhitelistSheet(items: items)
                case let .supportedCountries(list): SupportedCountriesSheet(countries: list)
                }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } } }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }

    @ViewBuilder private var content: some View {
        ScrollView {
            if hSize == .compact {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if let customer { ProfileCard(customer: customer) }
                    esimDetailSection
                    esimListCard
                    ordersCard
                }
                .padding(Spacing.xl)
            } else {
                HStack(alignment: .top, spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        if let customer { ProfileCard(customer: customer) }
                        esimListCard
                        ordersCard
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        esimDetailSection
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .padding(Spacing.xl)
            }
        }
    }

    @ViewBuilder private var esimDetailSection: some View {
        switch detailPhase {
        case .idle:
            ContentUnavailableView("Select an eSIM", systemImage: "simcard",
                                   description: Text("Choose an eSIM from the list to see its eUICC, data usage, location, package, and sessions."))
                .frame(maxWidth: .infinity)
                .glassCard()
        case .loading:
            SectionCard(title: "eSIM details") {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, Spacing.sm)
            }
        case let .loaded(detail):
            EsimDetailCard(detail: detail) { sheet = $0 }
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn't load eSIM", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                if let iccid = selectedIccid ?? ref.iccid ?? esims.first?.iccid {
                    Button("Try Again") { Task { await loadDetail(iccid) } }
                        .buttonStyle(.glassProminent)
                }
            }
            .frame(maxWidth: .infinity)
            .glassCard()
        }
    }

    private var esimListCard: some View {
        SectionCard(title: "eSIMs (\(esims.count))") {
            if esims.isEmpty {
                Text("No eSIMs assigned.").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(esims) { e in
                    let isSelected = e.iccid == (selectedIccid ?? ref.iccid)
                    Button {
                        Task { await select(e.iccid) }
                    } label: {
                        HStack {
                            Image(systemName: "simcard").foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(e.iccid).font(.callout.monospaced()).lineLimit(1)
                            Spacer()
                            if let cov = e.coverageName { Text(cov).font(.caption).foregroundStyle(.secondary) }
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).font(.caption)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, Spacing.xs)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("eSIM \(e.iccid)\(e.coverageName.map { ", \($0)" } ?? "")")
                    .accessibilityHint("Shows this eSIM's details")
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }

    private var ordersCard: some View {
        SectionCard(title: "Recent orders (\(orders.count))") {
            if orders.isEmpty {
                Text("No orders.").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(orders) { o in
                    OrderRow(order: o)
                    if o.id != orders.last?.id { Divider() }
                }
            }
            if !ref.customerId.isEmpty {
                Button { showAllOrders = true } label: {
                    Label("View all orders", systemImage: "list.bullet.rectangle").font(.callout)
                }
                .padding(.top, orders.isEmpty ? 0 : Spacing.sm)
            }
        }
    }

    private func load() async {
        do {
            // ICCID-only deep link (no linked customer id): load the eSIM directly
            // rather than GET /api/customers/{tenant}// — that double slash gets a
            // Django 301 that drops the bearer, surfacing as a misleading
            // "session expired" instead of the eSIM the user searched for.
            if ref.customerId.isEmpty {
                guard let iccid = ref.iccid, !iccid.isEmpty else {
                    phase = .failed("Couldn't open — no customer or eSIM reference.")
                    return
                }
                customer = nil
                esims = []
                selectedIccid = iccid
                await loadOrders(for: iccid)
                phase = .loaded
                await loadDetail(iccid)
                return
            }
            let q = ["customer__customer_id": ref.customerId, "limit": "10"]
            let cust = try await client.get("/api/customers/\(ref.tenant)/\(ref.customerId)/", query: [:],
                                            as: SingleCustomerResponse.self)
            customer = cust.customer
            esims = (try? await client.get("/api/esims/\(ref.tenant)/", query: q, as: AssignedEsimsPage.self))?.esims ?? []
            let iccid = selectedIccid ?? ref.iccid ?? esims.first?.iccid
            if let iccid {
                selectedIccid = iccid
                await loadOrders(for: iccid)
            }
            phase = .loaded
            if let iccid { await loadDetail(iccid) }
        } catch let error as APIError {
            phase = .failed(adminErrorMessage(error))
        } catch is CancellationError {
            // View navigated away mid-load — not a real error.
        } catch {
            phase = .failed("Unexpected error.")
        }
    }

    /// Selecting an eSIM reloads both its detail panel and its orders.
    private func select(_ iccid: String) async {
        selectedIccid = iccid
        await loadOrders(for: iccid)
        await loadDetail(iccid)
    }

    private func loadOrders(for iccid: String) async {
        let q = ["iccid": iccid, "limit": "10"]
        orders = (try? await client.get("/api/orders/\(ref.tenant)/", query: q, as: OrdersPage.self))?.orders ?? []
    }

    private func loadDetail(_ iccid: String) async {
        detailPhase = .loading
        do {
            let resp = try await client.get("/api/esim/\(iccid)/", query: [:], as: EsimDetailResponse.self)
            if let e = resp.esim {
                detailPhase = .loaded(e)
            } else {
                detailPhase = .failed("The eSIM response didn't contain detail.")
            }
        } catch let error as APIError {
            detailPhase = .failed(adminErrorMessage(error))
        } catch is CancellationError {
            // View navigated away mid-load — not a real error.
        } catch {
            detailPhase = .failed("Unexpected error loading eSIM detail.")
        }
    }
}

// MARK: - Orders

/// One order row, shared by the eSIM-scoped "Recent orders" card and the
/// "All orders" sheet.
private struct OrderRow: View {
    let order: Order

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Leading accent encodes the payment category (the web colors the whole row).
            RoundedRectangle(cornerRadius: 1.5).fill(tint ?? .clear).frame(width: 3)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(order.packageName.isEmpty ? order.orderNumber : order.packageName)
                        .font(.subheadline.weight(.medium)).lineLimit(1)
                    Spacer(minLength: Spacing.sm)
                    priceView
                }
                HStack(spacing: Spacing.xs + 2) {
                    StatusBadge(status: order.paymentStatus)
                    if !order.orderType.isEmpty { Text(order.orderType).font(.caption2).foregroundStyle(.secondary) }
                    if let code = order.discountCode {
                        Label(code, systemImage: "tag.fill").font(.caption2).foregroundStyle(.warning)
                    }
                    if let refund = order.refundLabel {
                        Text(refund).font(.caption2).foregroundStyle(.warning)
                    }
                    Spacer()
                    Text(shortDate(order.purchaseDate)).font(.caption2).foregroundStyle(.secondary)
                }
                if let country = order.purchaseCountry, !country.isEmpty {
                    Text("Purchased in \(country)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.a11yLabel(order))
    }

    @ViewBuilder private var priceView: some View {
        if order.isComplimentary {
            Text("Complimentary").font(.subheadline.weight(.medium)).foregroundStyle(.positive)
        } else {
            VStack(alignment: .trailing, spacing: 0) {
                if let struck = order.struckPriceDisplay {
                    Text(struck).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary).strikethrough()
                }
                Text(order.usdPriceDisplay).font(.subheadline.monospacedDigit())
                if let local = order.localPriceDisplay {
                    Text(local).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Mirrors the web's per-row color by payment state/type.
    private var tint: Color? {
        if order.paymentStatus == "refunded" { return .negative }
        if order.isComplimentary { return .positive }
        if order.paymentMethod == "agent_payment" { return .purple }
        if order.paymentMethod == "voucher" { return .teal }
        if order.discountCode != nil && order.paymentStatus == "success" { return .orange }
        return nil
    }

    /// One spoken sentence so VoiceOver reads the row as a unit.
    static func a11yLabel(_ o: Order) -> String {
        var parts = [o.packageName.isEmpty ? o.orderNumber : o.packageName,
                     o.isComplimentary ? "Complimentary" : o.usdPriceDisplay,
                     "Status: \(o.paymentStatus.capitalized)"]
        if !o.orderType.isEmpty { parts.append(o.orderType) }
        if let code = o.discountCode { parts.append("Discount \(code)") }
        if let refund = o.refundLabel { parts.append(refund) }
        parts.append(shortDate(o.purchaseDate))
        return parts.joined(separator: ", ")
    }
}

/// Every order for the customer (not just the selected eSIM), in a sheet.
private struct AllOrdersSheet: View {
    let client: LiveAPIClient
    let tenant: String
    let customerId: String

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    @State private var orders: [Order] = []
    @State private var total = 0
    enum Phase { case loading, loaded, failed(String) }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .failed(message):
                    ContentUnavailableView("Couldn't load orders", systemImage: "exclamationmark.triangle",
                                           description: Text(message))
                case .loaded:
                    if orders.isEmpty {
                        ContentUnavailableView("No orders", systemImage: "bag")
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(orders) { o in
                                    OrderRow(order: o).padding(.horizontal)
                                    if o.id != orders.last?.id { Divider().padding(.horizontal) }
                                }
                                if total > orders.count {
                                    Text("Showing \(orders.count) of \(total)")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity).padding()
                                }
                            }
                            .padding(.vertical, Spacing.sm)
                        }
                    }
                }
            }
            .navigationTitle("All orders")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 480)
        #endif
        .reload(on: customerId) { await load() }
    }

    private func load() async {
        do {
            let page = try await client.get("/api/orders/\(tenant)/",
                                            query: ["customer__customer_id": customerId, "limit": "100"],
                                            as: OrdersPage.self)
            orders = page.orders
            total = page.count
            phase = .loaded
        } catch is CancellationError {
        } catch let e as APIError {
            phase = .failed(adminErrorMessage(e))
        } catch {
            phase = .failed("Couldn't load orders.")
        }
    }
}

// MARK: - eSIM detail

private struct EsimDetailCard: View {
    let detail: EsimDetail
    var onView: (EsimDetailSheet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header
            if !euiccItems.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading),
                                    GridItem(.flexible(), alignment: .topLeading)],
                          alignment: .leading, spacing: Spacing.md) {
                    ForEach(euiccItems, id: \.0) { LabeledValue(label: $0.0, value: $0.1) }
                }
            }
            if !allSupportedCountries.isEmpty || !detail.whitelist.isEmpty {
                HStack(spacing: Spacing.md) {
                    Spacer()
                    if !allSupportedCountries.isEmpty {
                        viewButton("Supported countries (\(allSupportedCountries.count))",
                                   .supportedCountries(allSupportedCountries))
                    }
                    if !detail.whitelist.isEmpty {
                        viewButton("Whitelist (\(detail.whitelist.count))", .whitelist(detail.whitelist))
                    }
                }
            }
            divider
            dataUsageBlock
            divider; locationBlock(detail.latestLocation)
            divider; packageBlock(detail.activePackage)
            divider; sessionBlock(detail.openDataSessions.first)
        }
        .glassCard()
    }

    private var divider: some View { Divider().padding(.vertical, 1) }

    private func viewButton(_ title: String, _ sheet: EsimDetailSheet) -> some View {
        Button(title) { onView(sheet) }.font(.caption).buttonStyle(.borderless)
    }

    /// Unique sorted union of every package's supported countries (web aggregates these).
    private var allSupportedCountries: [String] {
        Array(Set(detail.packages.flatMap { $0.supportedCountries })).sorted()
    }

    /// A sub-section eyebrow with an optional "View all" affordance. Matches the
    /// eyebrow register of `SectionHeader` so the type system reads as one family.
    private func sectionHeader(_ title: String, view: EsimDetailSheet?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased()).eyebrow()
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let view { viewButton("View all", view) }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(detail.coverageName.map { "\($0) eSIM" } ?? "eSIM Details").font(.headline)
                Text(detail.iccid).font(.caption.monospaced()).foregroundStyle(.tint).textSelection(.enabled)
                    .accessibilityLabel("ICCID \(detail.iccid)")
                if let name = detail.esimName, !name.isEmpty {
                    Text(name).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                if let st = detail.euicc?.state {
                    Badge(text: st.capitalized, color: stateColor(st), systemImage: stateGlyph(st))
                        .accessibilityLabel("eUICC state: \(st.capitalized)")
                }
                Badge(text: detail.autoTopUp ? "Auto Top-Up On" : "Auto Top-Up Off",
                      color: detail.autoTopUp ? .blue : .secondary,
                      systemImage: detail.autoTopUp ? "arrow.triangle.2.circlepath" : "pause.circle")
                Badge(text: detail.archived ? "Archived" : "Active",
                      color: detail.archived ? .secondary : .positive,
                      systemImage: detail.archived ? "archivebox" : "checkmark.circle")
                    .accessibilityLabel(detail.archived ? "Archived" : "Active")
            }
        }
    }

    private var euiccItems: [(String, String)] {
        var items: [(String, String)] = []
        let e = detail.euicc
        if let s = e?.stateMessage ?? e?.state { items.append(("State", s)) }
        if let d = epochDate(e?.lastOperationDate) { items.append(("Last operation", d)) }
        if let n = e?.reuseRemainingCount { items.append(("Remaining reuse", e?.maxReuseCount.map { "\(n) / \($0)" } ?? "\(n)")) }
        if let imsi = detail.imsi, !imsi.isEmpty { items.append(("IMSI", imsi)) }
        if let cov = detail.coverageName { items.append(("Coverage", cov)) }
        if (e?.state ?? "").uppercased() == "RELEASED" {
            if let dp = detail.smDpAddress, !dp.isEmpty { items.append(("SM-DP+", dp)) }
            if let mid = detail.matchingId, !mid.isEmpty { items.append(("Activation", mid)) }
            if let lpa = e?.activationCode, !lpa.isEmpty { items.append(("LPA", lpa)) }
        }
        if let eid = e?.eid, !eid.isEmpty { items.append(("EID", eid)) }
        return items
    }

    @ViewBuilder private var dataUsageBlock: some View {
        let total = ((detail.totalDataAllowanceGB ?? 0) as NSDecimalNumber).doubleValue
        let remaining = ((detail.totalDataRemainingGB ?? 0) as NSDecimalNumber).doubleValue
        // Guard against NaN/inf — ProgressView crashes on a non-finite value.
        let fraction: Double = {
            guard total.isFinite, total > 0, remaining.isFinite else { return 1 }
            let f = remaining / total
            return f.isFinite ? min(max(f, 0), 1) : 1
        }()
        let unlimited = !(total.isFinite && total > 0)
        let usageText = unlimited ? "Unlimited" : "\(fmtGB(remaining)) of \(fmtGB(total)) left"
        VStack(alignment: .leading, spacing: Spacing.xs + 2) {
            HStack {
                Text("DATA").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(.tertiary)
                Spacer()
                Text(usageText)
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: fraction).tint(.accentColor)
                .accessibilityLabel("Data remaining")
                .accessibilityValue(usageText)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func locationBlock(_ loc: EsimLocation?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("LAST LOCATION", view: .locations(detail.iccid))
            if let loc {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(loc.countryName ?? "—").font(.callout)
                        Spacer()
                        if let op = loc.operator {
                            OperatorAllowance(operatorName: op, dataAllowed: loc.dataAllowed)
                        }
                    }
                    if let when = epochDate(loc.dateEpoch) {
                        Text(when).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("No location data.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func packageBlock(_ pkg: EsimPackage?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("ACTIVE PACKAGE", view: detail.packages.isEmpty ? nil : .packages(detail.packages))
            if let pkg {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pkg.displayName).font(.callout)
                    if !pkg.supportedCountries.isEmpty {
                        Text("\(pkg.supportedCountries.count) countries").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("No active package.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func sessionBlock(_ s: OpenDataSession?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("OPEN DATA SESSION", view: .sessions(detail.iccid))
            if let s {
                HStack {
                    Text(detail.coverageName ?? "—").font(.callout)
                    if let when = epochDate(s.openedDate) {
                        Text(when).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    // usage_kb is fed to a byte-based formatter to match the web exactly.
                    if let kb = s.usageKb { Text(fmtBytes(kb)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("No open sessions.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Detail sheets

enum EsimDetailSheet: Identifiable {
    case locations(String)
    case sessions(String)
    case packages([EsimPackage])
    case whitelist([Whitelist])
    case supportedCountries([String])
    var id: String {
        switch self {
        case .locations: "locations"
        case .sessions: "sessions"
        case .packages: "packages"
        case .whitelist: "whitelist"
        case .supportedCountries: "supportedCountries"
        }
    }
}

private struct LocationsSheet: View {
    let session: Session
    let iccid: String
    @Environment(\.tokenProvider) private var tokenProvider
    @State private var rows: [EsimLocation] = []
    @State private var loading = true
    @State private var error: String?
    var body: some View {
        listOrEmpty(loading: loading, count: rows.count, empty: "No location history.",
                    error: error, retry: { Task { await load() } }) {
            ForEach(rows) { loc in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(loc.countryName ?? "—").font(.body)
                        Spacer()
                        if let op = loc.operator {
                            OperatorAllowance(operatorName: op, dataAllowed: loc.dataAllowed, font: .caption)
                        }
                    }
                    if let when = epochDate(loc.dateEpoch) { Text(when).font(.caption).foregroundStyle(.secondary) }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Locations")
        .reload(on: iccid) { await load() }
    }

    private func load() async {
        loading = true; error = nil
        let client = LiveAPIClient(host: session.host, tokenProvider: tokenProvider)
        do {
            rows = try await client.get("/api/esim/\(iccid)/location/", query: ["limit": "100"], as: EsimLocationList.self).results
        } catch is CancellationError {
            return
        } catch let e as APIError {
            error = adminErrorMessage(e)
        } catch {
            self.error = "Couldn't load location history."
        }
        loading = false
    }
}

private struct SessionsSheet: View {
    let session: Session
    let iccid: String
    @Environment(\.tokenProvider) private var tokenProvider
    @State private var rows: [EsimSession] = []
    @State private var loading = true
    @State private var error: String?
    var body: some View {
        listOrEmpty(loading: loading, count: rows.count, empty: "No sessions.",
                    error: error, retry: { Task { await load() } }) {
            ForEach(rows) { s in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(s.countryName ?? "—").font(.body)
                        if let t = s.type { Text(t).font(.caption2).foregroundStyle(.tertiary) }
                        Spacer()
                        // Usage is the byte-count "duration" field (matches the web).
                        Text(fmtBytes(s.durationBytes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if let when = epochDate(s.connectTimeEpoch) {
                        Text("Connected \(when)").font(.caption2).foregroundStyle(.secondary)
                    }
                    if let when = epochDate(s.closeTimeEpoch) {
                        Text("Closed \(when)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Sessions")
        .reload(on: iccid) { await load() }
    }

    private func load() async {
        loading = true; error = nil
        let client = LiveAPIClient(host: session.host, tokenProvider: tokenProvider)
        do {
            rows = try await client.get("/api/esim/\(iccid)/cdr/", query: ["limit": "100"], as: EsimSessionList.self).results
        } catch is CancellationError {
            return
        } catch let e as APIError {
            error = adminErrorMessage(e)
        } catch {
            self.error = "Couldn't load sessions."
        }
        loading = false
    }
}

private struct PackagesSheet: View {
    let packages: [EsimPackage]
    var body: some View {
        listOrEmpty(loading: false, count: packages.count, empty: "No packages.") {
            ForEach(packages) { pkg in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(pkg.displayName).font(.body)
                        Spacer()
                        if let s = pkg.status { StatusBadge(status: s) }
                    }
                    ForEach(detailLines(pkg), id: \.self) { line in
                        Text(line).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Packages")
    }

    /// Status-dependent detail lines, mirroring the web's package modal columns.
    private func detailLines(_ pkg: EsimPackage) -> [String] {
        var lines: [String] = []
        switch (pkg.status ?? "").uppercased() {
        case "NOT_ACTIVE":
            let start = epochDate(pkg.windowActivationStartEpoch)
            let end = epochDate(pkg.windowActivationEndEpoch)
            if start != nil || end != nil { lines.append("Window \(start ?? "—") – \(end ?? "—")") }
        case "TERMINATED":
            if let d = epochDate(pkg.dateTerminatedEpoch) { lines.append("Terminated \(d)") }
        default:
            if let d = epochDate(pkg.dateActivatedEpoch) { lines.append("Activated \(d)") }
            if !pkg.isUnlimited, let r = pkg.dataUsageRemainingBytes { lines.append("\(fmtBytes(r)) left") }
        }
        if let used = pkg.dataUsedBytes { lines.append("\(fmtBytes(used)) used") }
        if !pkg.supportedCountries.isEmpty { lines.append("\(pkg.supportedCountries.count) countries") }
        return lines
    }
}

private struct WhitelistSheet: View {
    let items: [Whitelist]
    var body: some View {
        listOrEmpty(loading: false, count: items.count, empty: "No whitelist entries.") {
            ForEach(items) { w in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(w.country ?? "—").font(.body)
                        Spacer()
                        if let op = w.operator {
                            OperatorAllowance(operatorName: op, dataAllowed: w.dataAllowed, font: .caption)
                        }
                    }
                    HStack(spacing: Spacing.sm) {
                        if let n = w.whitelistName { Text(n).font(.caption2).foregroundStyle(.secondary) }
                        if let bc = w.bestConnectivity { Text(bc).font(.caption2).foregroundStyle(.tertiary) }
                        if let lte = w.lteSupport, !lte.isEmpty {
                            Text("LTE \(lte)").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    if w.androidAutoApn != nil || w.iosAutoApn != nil {
                        HStack(spacing: Spacing.sm) {
                            if let a = w.androidAutoApn { apnFlag("Android APN", a) }
                            if let i = w.iosAutoApn { apnFlag("iOS APN", i) }
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Whitelist")
    }

    private func apnFlag(_ label: String, _ on: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: on ? "checkmark.circle.fill" : "xmark.circle")
                .font(.caption2).foregroundStyle(on ? .positive : .tertiary)
            Text(label).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

/// Searchable union of countries supported across all of an eSIM's packages.
private struct SupportedCountriesSheet: View {
    let countries: [String]
    @State private var query = ""
    private var filtered: [String] {
        query.isEmpty ? countries : countries.filter { $0.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        listOrEmpty(loading: false, count: filtered.count, empty: "No countries.") {
            ForEach(filtered, id: \.self) { Text($0).font(.body) }
        }
        .navigationTitle("Supported countries")
        .searchable(text: $query)
    }
}

@ViewBuilder
private func listOrEmpty<Content: View>(loading: Bool, count: Int, empty: String,
                                        error: String? = nil, retry: (() -> Void)? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
    if let error {
        ContentUnavailableView {
            Label("Couldn't load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            if let retry { Button("Try Again", action: retry).buttonStyle(.glassProminent) }
        }
    } else if loading {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if count == 0 {
        ContentUnavailableView(empty, systemImage: "tray")
    } else {
        List { content() }
    }
}

private struct LabeledValue: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.monospaced()).textSelection(.enabled)
                .lineLimit(2).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Shared building blocks

/// Formats a server epoch (seconds or milliseconds) as a UTC wall-clock string,
/// e.g. "Jun 20, 2026 at 2:10 PM UTC". Every backend timestamp is UTC, so we pin
/// the zone and label it — matching the web admin's `from_timestamp()`. Returning
/// the " UTC" suffix here keeps it the single source of truth for all call sites.
private func epochDate(_ e: Double?) -> String? {
    guard let e, e.isFinite, e > 0, e < 1e15 else { return nil }
    let seconds = e > 1_000_000_000_000 ? e / 1000 : e
    var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
    style.timeZone = TimeZone(identifier: "UTC")!
    return Date(timeIntervalSince1970: seconds).formatted(style) + " UTC"
}

private func fmtGB(_ gb: Double) -> String {
    guard gb.isFinite else { return "—" }
    if gb < 0 { return "Unlimited" }   // negative allowance = unlimited (matches the web)
    return gb >= 1 ? String(format: "%.1fGB", gb) : String(format: "%.0fMB", gb * 1024)
}

/// Human-readable byte count, mirroring the web `format_bytes` (scales B→TB at
/// 1024 steps, 2 decimals; 0/absent → "0 GB", negative → "Unlimited"). Used for
/// a session's raw byte-count "duration".
private func fmtBytes(_ bytes: Double?) -> String {
    guard let b = bytes, b.isFinite else { return "—" }
    if b < 0 { return "Unlimited" }
    if b == 0 { return "0 GB" }
    let units = ["B", "KB", "MB", "GB", "TB"]
    var v = b, i = 0
    while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
    return String(format: "%.2f %@", v, units[i])
}

/// Colour an eUICC state badge by meaning — the web shows no colour, but a flat
/// green badge wrongly implies "all good" for ERROR/DISABLED states. Anchored to
/// the design system's `StatusStyle` for the states it knows, with eUICC-specific
/// nuance on top (DISABLED/DELETED read as a warning, UNKNOWN as a problem).
private func stateColor(_ state: String) -> Color {
    switch state.uppercased() {
    case "DISABLED", "DELETED": return .warning
    case "UNKNOWN": return .negative
    default:
        let c = StatusStyle.color(state)
        return c == .secondary ? .secondary : c
    }
}

/// A glyph that carries the eUICC state's meaning without relying on colour, so
/// the badge is legible to colour-blind users and VoiceOver alike.
private func stateGlyph(_ state: String) -> String {
    switch state.uppercased() {
    case "RELEASED", "ENABLED", "INSTALLED": return "checkmark.circle"
    case "DISABLED", "DELETED": return "pause.circle"
    case "ERROR", "UNKNOWN": return "exclamationmark.triangle"
    default: return "questionmark.circle"
    }
}

/// Shows a roaming operator and whether data is allowed on it. Meaning rides on
/// a glyph + spoken label (allowed/blocked), with colour as reinforcement only —
/// never the sole signal. Reused by the location, locations-history, and
/// whitelist rows so allowed/blocked reads identically everywhere.
private struct OperatorAllowance: View {
    let operatorName: String
    let dataAllowed: Bool
    var font: Font = .caption.weight(.medium)
    var body: some View {
        Label {
            Text(operatorName)
        } icon: {
            Image(systemName: dataAllowed ? "checkmark.circle" : "xmark.circle")
        }
        .labelStyle(.titleAndIcon)
        .font(font)
        .foregroundStyle(dataAllowed ? Color.positive : Color.negative)
        .accessibilityElement()
        .accessibilityLabel("\(operatorName), \(dataAllowed ? "Data allowed" : "Data blocked")")
    }
}

private struct ProfileCard: View {
    let customer: Customer
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(customer.displayName).font(.title2.weight(.semibold))
            HStack(spacing: Spacing.sm) {
                Badge(text: customer.isActive ? "Active" : "Disabled",
                      color: customer.isActive ? .positive : .negative,
                      systemImage: customer.isActive ? "checkmark.circle" : "xmark.circle")
                if customer.email != nil {
                    Badge(text: customer.emailVerified ? "Email verified" : "Email not verified",
                          color: customer.emailVerified ? .positive : .warning,
                          systemImage: customer.emailVerified ? "checkmark.seal" : "exclamationmark.circle")
                }
            }
            if let email = customer.email { Field("Email", email) }
            if let phone = customer.phoneNumber, !phone.isEmpty { Field("Phone", phone) }
            if let cid = customer.customerId { Field("Customer ID", cid) }
            if let created = customer.created { Field("Created", shortDate(created)) }
            if let ref = customer.externalReference, !ref.isEmpty { Field("External ref", ref) }
            if let pay = customer.paymentReference, !pay.isEmpty { Field("Payment ref", pay) }
            if let prov = customer.signInProvider, !prov.isEmpty { Field("Sign-in", prov) }
            if let code = customer.uniqueReferralCode, !code.isEmpty { Field("Referral code", code) }
            if !customer.notificationGroups.isEmpty {
                Divider().padding(.vertical, 1)
                NotificationPrefsView(groups: customer.notificationGroups)
            }
        }
        .glassCard()
    }
}

/// Read-only notification opt-ins, mirroring the web's preferences block.
private struct NotificationPrefsView: View {
    let groups: [(String, [(String, Bool)])]
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("NOTIFICATIONS").eyebrow()
            ForEach(groups, id: \.0) { group in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(group.0).font(.caption).foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                    ForEach(group.1, id: \.0) { item in
                        HStack(spacing: 3) {
                            Image(systemName: item.1 ? "checkmark.circle.fill" : "circle")
                                .font(.caption2).foregroundStyle(item.1 ? .positive : .tertiary)
                            Text(item.0).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(group.0): " + group.1.map { "\($0.0) \($0.1 ? "on" : "off")" }.joined(separator: ", "))
            }
        }
    }
}

private struct Field: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        HStack(alignment: .top) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: Spacing.md)
            Text(value).font(.callout.monospaced()).multilineTextAlignment(.trailing)
                .textSelection(.enabled).lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

