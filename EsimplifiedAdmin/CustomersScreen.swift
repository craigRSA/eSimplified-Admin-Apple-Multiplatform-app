import SwiftUI
import EsimplifiedKit

struct CustomersScreen: View {
    let session: Session
    var tenant: String?

    @Environment(\.tokenProvider) private var tokenProvider
    @State private var phase: Phase = .loading
    @State private var search = ""
    @State private var activeFilter: CustomerFilter = .active

    enum Phase { case loading, loaded([Customer]), failed(String) }

    var body: some View {
        NavigationStack {
            Group {
                if tenant == nil {
                    // The customers list is tenant-scoped (the web doesn't fetch
                    // without one). Prompt instead of hitting the unscoped endpoint.
                    QuietEmptyState(title: "Pick a tenant", systemImage: "building.2",
                                    message: "Choose a tenant in the toolbar to view its customers.")
                } else {
                    switch phase {
                    case .loading:
                        List {
                            ForEach(0..<8, id: \.self) { _ in
                                CustomerRowSkeleton().listRowSeparator(.hidden)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    case let .failed(message):
                        ContentUnavailableView {
                            Label("Couldn't load customers", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(message)
                        } actions: {
                            Button("Try Again") { Task { await load() } }
                                .buttonStyle(.glassProminent)
                        }
                    case let .loaded(customers):
                        if customers.isEmpty {
                            ContentUnavailableView("No customers", systemImage: "person.2.slash")
                        } else {
                            List(customers) { customer in
                                // The screen is tenant-gated here, so `tenant` is non-nil.
                                NavigationLink(value: CustomerRef(tenant: tenant ?? "",
                                                                  customerId: customer.customerId ?? "")) {
                                    CustomerRow(customer: customer)
                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                        }
                    }
                }
            }
            .background(AppBackground())
            .navigationDestination(for: CustomerRef.self) { CustomerDetailScreen(session: session, ref: $0) }
            .navigationTitle("Customers")
            .searchable(text: $search, prompt: "Name, email, phone")
            .debouncedSearch(of: search) { await load() }
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
            .refreshCommand { Task { await load() } }
        }
    }

    private func load() async {
        // Tenant-scoped: don't fetch the unscoped endpoint (it returns nothing).
        guard let tenant else { return }
        do {
            let client = LiveAPIClient(host: session.host, tokenProvider: tokenProvider)
            let path = "/api/customers/\(tenant)/"
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
        VStack(alignment: .leading, spacing: Spacing.xs) {
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
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(customer.displayName), \(customer.isActive ? "active" : "inactive")")
    }
}

/// Redacted placeholder row so the list doesn't pop in from a blank spinner.
private struct CustomerRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SkeletonBar(width: 180, height: 16)
            SkeletonBar(width: 120, height: 12)
        }
        .padding(.vertical, Spacing.xs)
    }
}
