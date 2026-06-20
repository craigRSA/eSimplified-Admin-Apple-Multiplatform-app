import SwiftUI
import EsimplifiedKit

/// Agent-payment orders — reuses /api/orders/ with payment_method=agent_payment
/// (server-side), showing both Pending and Success like the web approvals page,
/// with the actionable pending ones surfaced first. (Read-only; approving posts
/// to /purchase/webhook/ and is a later slice.)
struct AgentApprovalsScreen: View {
    let session: Session
    var tenant: String?

    @Environment(\.tokenProvider) private var tokenProvider
    @State private var phase: Phase = .loading

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
                    ContentUnavailableView("No agent orders", systemImage: "checkmark.seal",
                                           description: Text("No agent-payment orders for this tenant."))
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
    }

    private func load() async {
        do {
            let client = LiveAPIClient(host: session.host, tokenProvider: tokenProvider)
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
