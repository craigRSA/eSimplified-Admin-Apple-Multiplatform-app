import SwiftUI
import EsimplifiedKit

/// Mirrors the web's two searches: by customer (name/email/phone within a
/// tenant) and by ICCID (global). Results open the customer detail screen.
struct SearchScreen: View {
    let session: Session
    let tenants: [Tenant]
    @Binding var selectedTenant: Tenant?
    @Binding var focusSearchField: Bool

    enum Mode: String, CaseIterable, Identifiable {
        case customer = "Customer", iccid = "ICCID"
        var id: String { rawValue }
    }

    @Environment(\.tokenProvider) private var tokenProvider
    @FocusState private var searchFocused
    @State private var mode: Mode = .customer
    @State private var term = ""
    @State private var phase: Phase = .idle

    enum Phase { case idle, loading, customers([Customer]), esim(EsimSummary, String), empty(String), failed(String) }

    private var tenantScope: String? { selectedTenant?.schemaName }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchPanel
                    .padding(Spacing.lg)
                Divider()
                mainContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppBackground())
            .navigationTitle("Search")
            .navigationDestination(for: CustomerRef.self) { CustomerDetailScreen(session: session, ref: $0) }
            .onChange(of: mode) { _, _ in phase = .idle; term = "" }
            .onChange(of: selectedTenant) { _, _ in phase = .idle }
            .onChange(of: focusSearchField) { _, focus in
                if focus { applySearchFocus() }
            }
            .onAppear { if focusSearchField { applySearchFocus() } }
            .searchFocusCommand { applySearchFocus() }
        }
        .searchable(text: $term, prompt: promptText)
        .onSubmit(of: .search) { Task { await run() } }
    }

    private func applySearchFocus() {
        focusSearchField = false
        searchFocused = true
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Picker("Search by", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if mode == .customer && tenants.count > 1 {
                Picker("Tenant", selection: $selectedTenant) {
                    Text("Select a tenant").tag(Optional<Tenant>.none)
                    ForEach(tenants) { tenant in
                        Text(tenant.name).tag(Optional(tenant))
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(promptText, text: $term)
                    .textFieldStyle(.plain)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(mode == .iccid ? .numberPad : .default)
                    #endif
                    .focused($searchFocused)
                    .onSubmit { Task { await run() } }

                Button("Search") { Task { await run() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSearch)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm + 2)
            .background {
                RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    .fill(.quaternary.opacity(0.35))
            }

            if mode == .customer && selectedTenant == nil && tenants.count > 1 {
                Text("Pick a tenant to search customers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 540, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { searchFocused = true }
    }

    @ViewBuilder private var mainContent: some View {
        switch phase {
        case .idle:
            Spacer(minLength: 0)
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .customers(list):
            resultsScaffold(count: list.count) {
                List(list) { c in
                    NavigationLink(value: CustomerRef(tenant: tenantScope ?? "",
                                                    customerId: c.customerId ?? "")) {
                        CustomerSearchRow(customer: c)
                    }
                    .listRowInsets(Self.rowInsets)
                    .listRowSeparator(.visible)
                    .listRowBackground(Color.clear)
                }
            }
        case let .esim(esim, esimTenant):
            resultsScaffold(count: 1) {
                List {
                    NavigationLink(value: CustomerRef(tenant: esimTenant,
                                                      customerId: esim.customer?.customerId ?? "",
                                                      iccid: esim.iccid)) {
                        EsimSearchRow(esim: esim, tenant: esimTenant)
                    }
                    .listRowInsets(Self.rowInsets)
                    .listRowSeparator(.visible)
                    .listRowBackground(Color.clear)
                }
            }
        case let .empty(message):
            ContentUnavailableView(message, systemImage: "magnifyingglass")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView {
                Label("Search failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await run() } }
                    .buttonStyle(.glassProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func resultsScaffold<Content: View>(count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(count == 1 ? "1 result" : "\(count) results")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            Divider()
            content()
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
        }
    }

    private var promptText: String {
        mode == .iccid ? "ICCID (starts with 89…)" : "Name, email, or phone"
    }

    private var canSearch: Bool {
        let t = term.trimmingCharacters(in: .whitespaces)
        return mode == .iccid ? !t.isEmpty : (t.count >= 3 && tenantScope != nil)
    }

    private static let rowInsets = EdgeInsets(top: Spacing.sm, leading: Spacing.lg,
                                              bottom: Spacing.sm, trailing: Spacing.lg)

    private func run() async {
        let t = term.trimmingCharacters(in: .whitespaces)
        guard canSearch else { return }
        phase = .loading
        do {
            let client = LiveAPIClient(host: session.host, tokenProvider: tokenProvider)
            if mode == .iccid {
                let resp = try await client.get("/api/esim/\(t)/", query: ["search": "true"], as: EsimSearchResponse.self)
                if let e = resp.esim, !e.iccid.isEmpty {
                    phase = .esim(e, resp.tenant ?? tenantScope ?? "")
                } else {
                    phase = .empty("No eSIM found for that ICCID.")
                }
            } else {
                guard let tn = tenantScope else { phase = .idle; return }
                let page = try await client.get("/api/customers/\(tn)/", query: ["search": t], as: CustomersPage.self)
                phase = page.customers.isEmpty ? .empty("No customers found.") : .customers(page.customers)
            }
        } catch let error as APIError {
            if case let .requestFailed(400, message) = error,
               message?.contains("Unable to find requested resource") == true {
                phase = .empty(mode == .iccid ? "No eSIM found for that ICCID." : "No customers found.")
            } else {
                phase = .failed(searchErrorMessage(error))
            }
        } catch is CancellationError {
            // View navigated away mid-search — not a real error.
        } catch {
            phase = .failed("Unexpected error.")
        }
    }

    private func searchErrorMessage(_ error: APIError) -> String {
        switch error {
        case .unreachable: return "Couldn't reach the server."
        case .authExpired: return "Your session expired — sign in again."
        case .notFound: return "Not found."
        case let .requestFailed(code, message):
            if let message, message.hasPrefix("{") { return "Request failed (\(code))." }
            return message.map { "Server (\(code)): \($0)" } ?? "Request failed (\(code))."
        case .decoding: return "Couldn't read the server response."
        }
    }
}

// MARK: - Rows

private struct CustomerSearchRow: View {
    let customer: Customer

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(customer.displayName)
                .font(.body.weight(.medium))
            if let email = customer.email, !email.isEmpty, email != customer.displayName {
                Text(email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let phone = customer.phoneNumber, !phone.isEmpty {
                Text(phone)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

private struct EsimSearchRow: View {
    let esim: EsimSummary
    let tenant: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(esim.iccid)
                .font(.body.weight(.medium).monospaced())
                .lineLimit(1)
            if let who = esim.customer?.displayName {
                Text(who).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: Spacing.sm) {
                if let cov = esim.coverageName {
                    Label(cov, systemImage: "globe")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !tenant.isEmpty {
                    Text(tenant).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}
