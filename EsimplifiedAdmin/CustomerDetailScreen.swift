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
    @State private var phase: Phase = .loading
    @State private var esims: [EsimSummary] = []
    @State private var orders: [Order] = []
    @State private var detailPhase: DetailPhase = .idle
    @State private var selectedIccid: String?
    @State private var customer: Customer?

    enum Phase { case loading, loaded, failed(String) }
    enum DetailPhase { case idle, loading, loaded(EsimDetail), failed(String) }

    private var client: LiveAPIClient { LiveAPIClient(host: session.host, accessToken: session.accessToken) }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView("Couldn't load customer", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            case .loaded:
                content
            }
        }
        .navigationTitle(customer?.displayName ?? "Customer")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .background(AppBackground())
        .reload(on: ref.customerId) { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder private var content: some View {
        ScrollView {
            if hSize == .compact {
                VStack(alignment: .leading, spacing: 18) {
                    if let customer { ProfileCard(customer: customer) }
                    esimDetailSection
                    esimListCard
                    ordersCard
                }
                .padding(20)
            } else {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 18) {
                        if let customer { ProfileCard(customer: customer) }
                        esimListCard
                        ordersCard
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    VStack(alignment: .leading, spacing: 18) {
                        esimDetailSection
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .padding(20)
            }
        }
    }

    @ViewBuilder private var esimDetailSection: some View {
        switch detailPhase {
        case .idle:
            EmptyView()
        case .loading:
            SectionCard(title: "eSIM details") {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
            }
        case let .loaded(detail):
            EsimDetailCard(detail: detail)
        case let .failed(message):
            SectionCard(title: "eSIM details") {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var esimListCard: some View {
        SectionCard(title: "eSIMs (\(esims.count))") {
            if esims.isEmpty {
                Text("No eSIMs assigned.").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(esims) { e in
                    Button {
                        selectedIccid = e.iccid
                        Task { await loadDetail(e.iccid) }
                    } label: {
                        HStack {
                            Image(systemName: "simcard").foregroundStyle(.secondary)
                            Text(e.iccid).font(.callout.monospaced()).lineLimit(1)
                            Spacer()
                            if let cov = e.coverageName { Text(cov).font(.caption).foregroundStyle(.secondary) }
                            if e.iccid == (selectedIccid ?? ref.iccid) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).font(.caption)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
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
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(o.packageName.isEmpty ? o.orderNumber : o.packageName)
                                .font(.subheadline.weight(.medium)).lineLimit(1)
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(o.usdPriceDisplay).font(.subheadline.monospacedDigit())
                                if let local = o.localPriceDisplay {
                                    Text(local).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                        HStack(spacing: 6) {
                            StatusBadge(status: o.paymentStatus)
                            if !o.orderType.isEmpty { Text(o.orderType).font(.caption2).foregroundStyle(.secondary) }
                            if let code = o.discountCode {
                                Label(code, systemImage: "tag.fill").font(.caption2).foregroundStyle(.orange)
                            }
                            Spacer()
                            Text(shortDate(o.purchaseDate)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                    if o.id != orders.last?.id { Divider() }
                }
            }
        }
    }

    private func load() async {
        do {
            let q = ["customer__customer_id": ref.customerId, "limit": "10"]
            let cust = try await client.get("/api/customers/\(ref.tenant)/\(ref.customerId)/", query: [:],
                                            as: SingleCustomerResponse.self)
            customer = cust.customer
            esims = (try? await client.get("/api/esims/\(ref.tenant)/", query: q, as: AssignedEsimsPage.self))?.esims ?? []
            orders = (try? await client.get("/api/orders/\(ref.tenant)/", query: q, as: OrdersPage.self))?.orders ?? []
            phase = .loaded
            let iccid = selectedIccid ?? ref.iccid ?? esims.first?.iccid
            if let iccid { await loadDetail(iccid) }
        } catch let error as APIError {
            phase = .failed(adminErrorMessage(error))
        } catch is CancellationError {
        } catch {
            phase = .failed("Unexpected error.")
        }
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
        } catch {
            detailPhase = .failed("Unexpected error loading eSIM detail.")
        }
    }
}

// MARK: - eSIM detail

private struct EsimDetailCard: View {
    let detail: EsimDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if !euiccItems.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading),
                                    GridItem(.flexible(), alignment: .topLeading)],
                          alignment: .leading, spacing: 12) {
                    ForEach(euiccItems, id: \.0) { LabeledValue(label: $0.0, value: $0.1) }
                }
            }
            divider
            dataUsageBlock
            if let loc = detail.latestLocation { divider; locationBlock(loc) }
            if let pkg = detail.activePackage { divider; packageBlock(pkg) }
            if let s = detail.openDataSessions.first { divider; sessionBlock(s) }
        }
        .glassCard()
    }

    private var divider: some View { Divider().padding(.vertical, 1) }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(detail.coverageName.map { "\($0) eSIM" } ?? "eSIM Details").font(.headline)
                Text(detail.iccid).font(.caption.monospaced()).foregroundStyle(.tint).textSelection(.enabled)
                if let name = detail.esimName, !name.isEmpty {
                    Text(name).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let st = detail.euicc?.state { Badge(text: st.capitalized, color: .green) }
                Badge(text: detail.autoTopUp ? "Auto Top-Up On" : "Auto Top-Up Off",
                      color: detail.autoTopUp ? .blue : .secondary)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DATA").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(.tertiary)
                Spacer()
                Text(unlimited ? "Unlimited" : "\(fmtGB(remaining)) of \(fmtGB(total)) left")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: fraction).tint(.accentColor)
        }
    }

    @ViewBuilder private func locationBlock(_ loc: EsimLocation) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("LAST LOCATION").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(.tertiary)
            HStack {
                Text(loc.countryName ?? "—").font(.callout)
                Spacer()
                if let op = loc.operator {
                    Text(op).font(.caption.weight(.medium)).foregroundStyle(loc.dataAllowed ? .green : .red)
                }
            }
            if let when = epochDate(loc.dateEpoch) {
                Text("\(when) UTC").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func packageBlock(_ pkg: EsimPackage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("ACTIVE PACKAGE").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(.tertiary)
            Text(pkg.name ?? "—").font(.callout)
            if !pkg.supportedCountries.isEmpty {
                Text("\(pkg.supportedCountries.count) countries").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func sessionBlock(_ s: OpenDataSession) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("OPEN DATA SESSION").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(.tertiary)
            HStack {
                Text(detail.coverageName ?? "—").font(.callout)
                if let when = epochDate(s.openedDate) {
                    Text(when).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if let kb = s.usageKb { Text(fmtKB(kb)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            }
        }
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
    }
}

// MARK: - Shared building blocks

private func epochDate(_ e: Double?) -> String? {
    guard let e, e.isFinite, e > 0, e < 1e15 else { return nil }
    let seconds = e > 1_000_000_000_000 ? e / 1000 : e
    return Date(timeIntervalSince1970: seconds).formatted(date: .abbreviated, time: .shortened)
}

private func fmtGB(_ gb: Double) -> String {
    guard gb.isFinite else { return "—" }
    return gb >= 1 ? String(format: "%.1fGB", gb) : String(format: "%.0fMB", gb * 1024)
}

private func fmtKB(_ kb: Double) -> String {
    if kb >= 1_048_576 { return String(format: "%.2fGB", kb / 1_048_576) }
    if kb >= 1024 { return String(format: "%.1fMB", kb / 1024) }
    return String(format: "%.0fKB", kb)
}

private struct ProfileCard: View {
    let customer: Customer
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(customer.displayName).font(.title2.weight(.semibold))
            HStack(spacing: 8) {
                Badge(text: customer.isActive ? "Active" : "Disabled", color: customer.isActive ? .green : .red)
                if customer.email != nil {
                    Badge(text: customer.emailVerified ? "Email verified" : "Email not verified",
                          color: customer.emailVerified ? .green : .orange)
                }
            }
            if let email = customer.email { Field("Email", email) }
            if let phone = customer.phoneNumber, !phone.isEmpty { Field("Phone", phone) }
            if let cid = customer.customerId { Field("Customer ID", cid) }
            if let created = customer.created { Field("Created", shortDate(created)) }
        }
        .glassCard()
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
        }
        .glassCard()
    }
}

private struct Field: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        HStack(alignment: .top) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).font(.callout.monospaced()).multilineTextAlignment(.trailing)
                .textSelection(.enabled).lineLimit(2)
        }
    }
}

private struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
