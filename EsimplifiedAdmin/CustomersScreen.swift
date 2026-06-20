import SwiftUI
import EsimplifiedKit

struct CustomersScreen: View {
    let session: Session
    var tenant: String?

    @State private var phase: Phase = .loading
    @State private var search = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var activeFilter: CustomerFilter = .active

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
                if customers.isEmpty {
                    ContentUnavailableView("No customers", systemImage: "person.2.slash")
                } else {
                    List(customers) { CustomerRow(customer: $0) }
                }
            }
        }
        .navigationTitle("Customers")
        .searchable(text: $search, prompt: "Name, email, phone")
        .onChange(of: search) { _, _ in debouncedSearch() }
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Show", selection: $activeFilter) {
                        ForEach(CustomerFilter.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Label(activeFilter.label, systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .onChange(of: activeFilter) { _, _ in Task { await load() } }
        .reload(on: tenant) { await load() }
        .refreshable { await load() }
        .autoRefresh { await load() }
    }

    /// Debounce keystrokes, then reload from the server (the web searches
    /// server-side; a local filter would only see the already-loaded rows).
    private func debouncedSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            await load()
        }
    }

    private func load() async {
        do {
            let client = LiveAPIClient(host: session.host, accessToken: session.accessToken)
            let path = tenant.map { "/api/customers/\($0)/" } ?? "/api/customers/"
            // Default is Active (matches the web server-side default); the toolbar
            // filter can switch to Inactive or All (which omits is_active).
            var query = ["limit": "500"]
            if let v = activeFilter.queryValue { query["is_active"] = v }
            let term = search.trimmingCharacters(in: .whitespaces)
            if !term.isEmpty { query["search"] = term }
            let page = try await client.get(path, query: query, as: CustomersPage.self)
            phase = .loaded(page.customers)
        } catch let error as APIError {
            phase = .failed(adminErrorMessage(error))
        } catch is CancellationError {
            // View navigated away mid-load — not a real error.
        } catch {
            phase = .failed("Unexpected error.")
        }
    }
}

/// Active / Inactive / All filter for the customers list. Default Active mirrors
/// the web's server-side default (is_active=true); All omits the param.
enum CustomerFilter: String, CaseIterable, Identifiable {
    case active, inactive, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .active: "Active"
        case .inactive: "Inactive"
        case .all: "All"
        }
    }
    /// The `is_active` query value, or nil to omit the param (= all).
    var queryValue: String? {
        switch self {
        case .active: "true"
        case .inactive: "false"
        case .all: nil
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
