import SwiftUI
import EsimplifiedKit

/// Pending agent orders awaiting approval — reuses /api/orders/, filtered to
/// agent-payment orders that are still pending. (Read-only; approving an order
/// posts to /purchase/webhook/ and is a later slice.)
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
                    ContentUnavailableView("Nothing to approve", systemImage: "checkmark.seal",
                                           description: Text("No pending agent orders."))
                } else {
                    List(orders) { OrderApprovalRow(order: $0) }
                }
            }
        }
        .navigationTitle("Agent Approvals")
        .task(id: tenant) { await load() }
        .refreshable { await load() }
        .autoRefresh { await load() }
    }

    private func load() async {
        do {
            let client = LiveAPIClient(host: session.host, accessToken: session.accessToken)
            let path = tenant.map { "/api/orders/\($0)/" } ?? "/api/orders/"
            let page = try await client.get(path, query: ["limit": "200"], as: OrdersPage.self)
            let pending = page.orders.filter {
                $0.paymentMethod == "agent_payment" && $0.paymentStatus.lowercased() == "pending"
            }
            phase = .loaded(pending)
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
