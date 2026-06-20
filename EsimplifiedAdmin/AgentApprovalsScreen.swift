import SwiftUI
import EsimplifiedKit

/// Agent-payment orders — reuses /api/orders/ with payment_method=agent_payment
/// (server-side), showing both Pending and Success like the web approvals page,
/// with the actionable pending ones surfaced first. (Read-only; approving posts
/// to /purchase/webhook/ and is a later slice.)
struct AgentApprovalsScreen: View {
    let session: Session
    var tenant: String?

    @State private var phase: Phase = .loading

    enum Phase { case loading, loaded([Order]), failed(String) }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView("Couldn't load approvals", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            case let .loaded(orders):
                if orders.isEmpty {
                    ContentUnavailableView("No agent orders", systemImage: "checkmark.seal",
                                           description: Text("No agent-payment orders for this tenant."))
                } else {
                    List(orders) { OrderApprovalRow(order: $0) }
                }
            }
        }
        .navigationTitle("Agent Approvals")
        .reload(on: tenant) { await load() }
        .refreshable { await load() }
        .autoRefresh { await load() }
    }

    private func load() async {
        do {
            let client = LiveAPIClient(host: session.host, accessToken: session.accessToken)
            let path = tenant.map { "/api/orders/\($0)/" } ?? "/api/orders/"
            let page = try await client.get(path, query: ["limit": "200", "payment_method": "agent_payment"],
                                            as: OrdersPage.self)
            // Server already restricts to agent_payment; show Pending and Success
            // (matches the web), surfacing the actionable pending ones first.
            let agent = page.orders.filter { $0.paymentMethod == "agent_payment" }
            let pendingFirst = agent.filter { $0.paymentStatus.lowercased() == "pending" }
                + agent.filter { $0.paymentStatus.lowercased() != "pending" }
            phase = .loaded(pendingFirst)
        } catch let error as APIError {
            phase = .failed(adminErrorMessage(error))
        } catch is CancellationError {
            // View navigated away mid-load — not a real error.
        } catch {
            phase = .failed("Unexpected error.")
        }
    }
}

private struct OrderApprovalRow: View {
    let order: Order

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(order.orderNumber.isEmpty ? order.packageName : order.orderNumber).font(.headline)
                Spacer()
                Text(order.priceDisplay).font(.headline.monospacedDigit())
            }
            HStack {
                StatusBadge(status: order.paymentStatus)
                Spacer()
                Text(shortDate(order.purchaseDate)).font(.caption).foregroundStyle(.secondary)
            }
            if let who = order.customerName ?? order.customerEmail, !who.isEmpty {
                Text(who).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
