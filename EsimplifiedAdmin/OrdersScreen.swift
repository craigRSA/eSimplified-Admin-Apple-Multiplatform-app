import SwiftUI
import EsimplifiedKit

struct OrdersScreen: View {
    let session: Session

    @State private var phase: Phase = .loading
    @State private var search = ""

    enum Phase { case loading, loaded([Order]), failed(String) }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView("Couldn't load orders", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            case let .loaded(orders):
                let shown = filtered(orders)
                if shown.isEmpty {
                    ContentUnavailableView("No orders", systemImage: "tray")
                } else {
                    List(shown) { OrderRow(order: $0) }
                }
            }
        }
        .navigationTitle("Order History")
        .searchable(text: $search, prompt: "Order #, customer, package")
        .task { await load() }
        .refreshable { await load() }
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
        do {
            let client = LiveAPIClient(host: session.host, accessToken: session.accessToken)
            let page = try await client.get("/api/orders/", query: [:], as: OrdersPage.self)
            phase = .loaded(page.orders)
        } catch let error as APIError {
            phase = .failed(adminErrorMessage(error))
        } catch {
            phase = .failed("Unexpected error.")
        }
    }
}

private struct OrderRow: View {
    let order: Order

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(order.orderNumber.isEmpty ? order.packageName : order.orderNumber)
                    .font(.headline)
                Spacer()
                Text(order.priceDisplay).font(.headline.monospacedDigit())
            }
            HStack(spacing: 8) {
                StatusBadge(status: order.paymentStatus)
                if !order.orderType.isEmpty {
                    Text(order.orderType).font(.caption2).foregroundStyle(.secondary)
                }
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
