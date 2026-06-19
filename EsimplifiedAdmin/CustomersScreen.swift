import SwiftUI
import EsimplifiedKit

struct CustomersScreen: View {
    let session: Session
    var tenant: String?

    @State private var phase: Phase = .loading
    @State private var search = ""

    enum Phase { case loading, loaded([Customer]), failed(String) }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView("Couldn't load customers", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            case let .loaded(customers):
                let shown = filtered(customers)
                if shown.isEmpty {
                    ContentUnavailableView("No customers", systemImage: "person.2.slash")
                } else {
                    List(shown) { CustomerRow(customer: $0) }
                }
            }
        }
        .navigationTitle("Customers")
        .searchable(text: $search, prompt: "Name, email, phone")
        .task(id: tenant) { await load() }
        .refreshable { await load() }
    }

    private func filtered(_ customers: [Customer]) -> [Customer] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return customers }
        return customers.filter {
            ($0.fullName ?? "").lowercased().contains(q)
            || ($0.email ?? "").lowercased().contains(q)
            || ($0.phoneNumber ?? "").lowercased().contains(q)
        }
    }

    private func load() async {
        do {
            let client = LiveAPIClient(host: session.host, accessToken: session.accessToken)
            let path = tenant.map { "/api/customers/\($0)/" } ?? "/api/customers/"
            let page = try await client.get(path, query: ["limit": "100"], as: CustomersPage.self)
            phase = .loaded(page.customers)
        } catch let error as APIError {
            phase = .failed(adminErrorMessage(error))
        } catch {
            phase = .failed("Unexpected error.")
        }
    }
}

private struct CustomerRow: View {
    let customer: Customer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(customer.displayName).font(.headline)
                Spacer()
                StatusBadge(status: customer.isActive ? "active" : "inactive")
            }
            if let email = customer.email, !email.isEmpty, email != customer.displayName {
                Text(email).font(.caption).foregroundStyle(.secondary)
            }
            if let phone = customer.phoneNumber, !phone.isEmpty {
                Text(phone).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
