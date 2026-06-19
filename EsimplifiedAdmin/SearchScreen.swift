import SwiftUI
import EsimplifiedKit

/// Global search across loaded customers and orders.
struct SearchScreen: View {
    let session: Session

    @State private var phase: Phase = .loading
    @State private var query = ""

    enum Phase { case loading, loaded(customers: [Customer], orders: [Order]), failed(String) }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView("Couldn't load search data", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            case let .loaded(customers, orders):
                results(customers: customers, orders: orders)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Customers and orders")
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder private func results(customers: [Customer], orders: [Order]) -> some View {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matchedCustomers = q.isEmpty ? [] : customers.filter {
            ($0.fullName ?? "").lowercased().contains(q) || ($0.email ?? "").lowercased().contains(q)
            || ($0.phoneNumber ?? "").lowercased().contains(q)
        }
        let matchedOrders = q.isEmpty ? [] : orders.filter {
            $0.orderNumber.lowercased().contains(q) || $0.packageName.lowercased().contains(q)
            || ($0.customerEmail ?? "").lowercased().contains(q)
        }
        if q.isEmpty {
            ContentUnavailableView("Search customers and orders", systemImage: "magnifyingglass",
                                   description: Text("Type a name, email, order number, or package."))
        } else if matchedCustomers.isEmpty && matchedOrders.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                if !matchedCustomers.isEmpty {
                    Section("Customers (\(matchedCustomers.count))") {
                        ForEach(matchedCustomers) { c in
                            VStack(alignment: .leading) {
                                Text(c.displayName).font(.headline)
                                if let e = c.email, e != c.displayName { Text(e).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                if !matchedOrders.isEmpty {
                    Section("Orders (\(matchedOrders.count))") {
                        ForEach(matchedOrders) { o in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(o.orderNumber.isEmpty ? o.packageName : o.orderNumber).font(.headline)
                                    StatusBadge(status: o.paymentStatus)
                                }
                                Spacer()
                                Text(o.priceDisplay).font(.headline.monospacedDigit())
                            }
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        do {
            let client = LiveAPIClient(host: session.host, accessToken: session.accessToken)
            async let customers = client.get("/api/customers/", query: [:], as: CustomersPage.self)
            async let orders = client.get("/api/orders/", query: [:], as: OrdersPage.self)
            phase = .loaded(customers: try await customers.customers, orders: try await orders.orders)
        } catch let error as APIError {
            phase = .failed(adminErrorMessage(error))
        } catch {
            phase = .failed("Unexpected error.")
        }
    }
}
