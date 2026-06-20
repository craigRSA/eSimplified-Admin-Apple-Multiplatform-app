import SwiftUI
import EsimplifiedKit

/// Agent-payment orders — reuses /api/orders/ with payment_method=agent_payment.
/// A status filter (default Requested = the pending ones awaiting approval) keeps
/// the actionable orders front and centre, with Approved and All a tap away.
/// (Read-only; approving posts to /purchase/webhook/ and is a later slice.)
struct AgentApprovalsScreen: View {
    let session: Session
    var tenant: String?

    @Environment(\.tokenProvider) private var tokenProvider
    @State private var phase: Phase = .loading
    @State private var filter: ApprovalFilter = .requested

    enum Phase { case loading, loaded([Order]), failed(String) }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                List {
                    ForEach(0..<8, id: \.self) { _ in
                        OrderApprovalRowSkeleton().listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            case let .failed(message):
                ContentUnavailableView {
                    Label("Couldn't load approvals", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                        .buttonStyle(.glassProminent)
                }
            case let .loaded(orders):
                if orders.isEmpty {
                    ContentUnavailableView(filter == .all ? "No agent orders" : "No \(filter.label.lowercased()) orders",
                                           systemImage: "checkmark.seal",
                                           description: Text("No agent-payment orders match this filter."))
                } else {
                    List(orders) { OrderApprovalRow(order: $0) }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                }
            }
        }
        .background(AppBackground())
        .navigationTitle("Agent Approvals")
        .reload(on: tenant) { await load() }
        .refreshable { await load() }
        .autoRefresh { await load() }
        .refreshCommand { Task { await load() } }
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Show", selection: $filter) {
                        ForEach(ApprovalFilter.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(filter.label, systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .onChange(of: filter) { _, _ in Task { await load() } }
    }

    private func load() async {
        do {
            let client = LiveAPIClient(host: session.host, tokenProvider: tokenProvider)
            let path = tenant.map { "/api/orders/\($0)/" } ?? "/api/orders/"
            var query = ["limit": "200", "payment_method": "agent_payment"]
            if let status = filter.status { query["payment_status"] = status }
            let page = try await client.get(path, query: query, as: OrdersPage.self)
            let agent = page.orders.filter { $0.paymentMethod == "agent_payment" }
            // "All" surfaces the actionable pending ones first; a single-status filter
            // is already homogeneous, so leave its order alone.
            let ordered = filter == .all
                ? agent.filter { $0.paymentStatus.lowercased() == "pending" }
                    + agent.filter { $0.paymentStatus.lowercased() != "pending" }
                : agent
            phase = .loaded(ordered)
        } catch let error as APIError {
            phase = .failed(adminErrorMessage(error))
        } catch is CancellationError {
            // View navigated away mid-load — not a real error.
        } catch {
            phase = .failed("Unexpected error.")
        }
    }
}

/// Status filter for agent approvals. Defaults to Requested — the pending orders
/// awaiting approval — so the actionable ones lead.
enum ApprovalFilter: String, CaseIterable, Identifiable {
    case requested, approved, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .requested: "Requested"
        case .approved: "Approved"
        case .all: "All"
        }
    }
    /// The `payment_status` query value, or nil to omit the param (= all).
    var status: String? {
        switch self {
        case .requested: "pending"
        case .approved: "success"
        case .all: nil
        }
    }
}

private struct OrderApprovalRow: View {
    let order: Order

    private var title: String { order.orderNumber.isEmpty ? order.packageName : order.orderNumber }
    private var who: String? {
        let name = order.customerName ?? order.customerEmail
        return (name?.isEmpty == false) ? name : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                // Match Orders/CustomerDetail: the normalized USD price, not the raw
                // local-currency `priceDisplay`, so the same order reads consistently.
                Text(order.usdPriceDisplay).font(.headline.monospacedDigit())
            }
            HStack {
                StatusBadge(status: order.paymentStatus)
                Spacer()
                Text(shortDate(order.purchaseDate)).font(.caption).foregroundStyle(.secondary)
            }
            if let who { Text(who).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [title, "Status \(order.paymentStatus.capitalized)", "\(order.usdPriceDisplay) USD",
                     shortDate(order.purchaseDate)]
        if let who { parts.append(who) }
        return parts.joined(separator: ", ")
    }
}

/// Redacted placeholder row so the list doesn't pop in from a blank spinner —
/// mirrors the shape of `OrderApprovalRow` (title + price, then status + date).
private struct OrderApprovalRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                SkeletonBar(width: 160, height: 16)
                Spacer()
                SkeletonBar(width: 60, height: 16)
            }
            SkeletonBar(width: 120, height: 12)
        }
        .padding(.vertical, Spacing.xs)
    }
}
