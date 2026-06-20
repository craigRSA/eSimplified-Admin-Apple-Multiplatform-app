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

    enum Phase { case loading, loaded, failed(String) }

    /// iPhone (compact) gets rich rows; Mac/iPad (regular) gets a columnar table.
    private var useTable: Bool { hSize != .compact }

    var body: some View {
        Group {
            switch phase {
            case .loading where orders.isEmpty:
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message) where orders.isEmpty:
                ContentUnavailableView("Couldn't load orders", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            default:
                let shown = filtered(orders)
                VStack(spacing: 0) {
                    OrdersCountHeader(showing: shown.count, total: total, filtering: !search.isEmpty)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                    Divider()
                    if shown.isEmpty {
                        ContentUnavailableView("No matching orders", systemImage: "tray")
                            .frame(maxHeight: .infinity)
                    } else if useTable {
                        OrdersTable(orders: shown)
                    } else {
                        List(shown) { OrderRow(order: $0) }.listStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Order History")
        .searchable(text: $search, prompt: "Package, customer, email, order #")
        .task(id: tenant) { await load() }
        .refreshable { await load() }
        .autoRefresh { await load() }
    }

    private func filtered(_ orders: [Order]) -> [Order] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return orders }
        return orders.filter {
            $0.orderNumber.lowercased().contains(q)
            || $0.packageName.lowercased().contains(q)
            || ($0.customerEmail ?? "").lowercased().contains(q)
            || ($0.customerName ?? "").lowercased().contains(q)
        }
    }

    private func load() async {
        if orders.isEmpty { phase = .loading }
        do {
            let client = LiveAPIClient(host: session.host, accessToken: session.accessToken)
            let path = tenant.map { "/api/orders/\($0)/" } ?? "/api/orders/"
            let page = try await client.get(path, query: ["limit": "100"], as: OrdersPage.self)
            orders = page.orders
            total = page.count
            phase = .loaded
        } catch let error as APIError {
            phase = .failed(adminErrorMessage(error))
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

/// Columnar table for Mac/iPad — mirrors the web's Order History columns.
private struct OrdersTable: View {
    let orders: [Order]

    var body: some View {
        Table(orders) {
            TableColumn("Tenant") { o in
                Text(o.tenant).foregroundStyle(orderAccent(o) ?? .primary)
            }
            TableColumn("Package") { o in
                Text(o.packageName).foregroundStyle(orderAccent(o) ?? .primary).lineLimit(1)
            }
            TableColumn("Customer") { o in
                VStack(alignment: .leading, spacing: 1) {
                    if let n = o.customerName, !n.isEmpty { Text(n).lineLimit(1) }
                    if let e = o.customerEmail, !e.isEmpty {
                        Text(e).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            TableColumn("Purchased In") { o in
                Text(o.purchaseCountry ?? "—").foregroundStyle(.secondary)
            }
            TableColumn("Type") { o in Text(o.orderType).foregroundStyle(.secondary) }
            TableColumn("Price") { o in Text(o.usdPriceDisplay).monospacedDigit() }
            TableColumn("Local") { o in
                Text(o.localPriceDisplay ?? "").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            TableColumn("Discount") { o in
                if let code = o.discountCode { Text(code).foregroundStyle(.orange) } else { Text("") }
            }
            TableColumn("Status") { o in StatusBadge(status: o.paymentStatus) }
            TableColumn("Date") { o in
                Text(shortDate(o.purchaseDate)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

private struct OrderRow: View {
    let order: Order

    private var accent: Color? { orderAccent(order) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(order.packageName.isEmpty ? order.orderNumber : order.packageName)
                    .font(.headline).foregroundStyle(accent ?? .primary).lineLimit(1)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(order.usdPriceDisplay).font(.headline.monospacedDigit())
                    if let local = order.localPriceDisplay {
                        Text(local).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 6) {
                StatusBadge(status: order.paymentStatus)
                if !order.orderType.isEmpty {
                    Text(order.orderType)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                if let code = order.discountCode {
                    Label(code, systemImage: "tag.fill")
                        .font(.caption2.weight(.medium)).foregroundStyle(.orange)
                        .labelStyle(.titleAndIcon)
                }
                Spacer(minLength: 8)
                Text(shortDate(order.purchaseDate)).font(.caption2).foregroundStyle(.secondary)
            }
            if let who = subtitle {
                Text(who).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 5)
    }

    private var subtitle: String? {
        let who = order.customerName ?? order.customerEmail
        let parts = [who, order.purchaseCountry, tenantName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    private var tenantName: String? { order.tenant.isEmpty ? nil : order.tenant }
}

struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(status.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status.lowercased() {
        case "success", "approved", "active": .green
        case "refunded", "cancelled": .red
        case "pending", "requested", "awaiting_s2s": .orange
        default: .secondary
        }
    }
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
