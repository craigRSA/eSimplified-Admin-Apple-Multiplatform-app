import SwiftUI
import EsimplifiedKit

/// Mirrors the web's two searches: by customer (name/email/phone within a
/// tenant) and by ICCID (global). Results open the customer detail screen.
struct SearchScreen: View {
    let session: Session
    var tenant: String?

    enum Mode: String, CaseIterable, Identifiable {
        case customer = "Customer", iccid = "ICCID"
        var id: String { rawValue }
    }

    @Environment(\.tokenProvider) private var tokenProvider
    @State private var mode: Mode = .customer
    @State private var term = ""
    @State private var phase: Phase = .idle

    enum Phase { case idle, loading, customers([Customer]), esim(EsimSummary, String), empty(String), failed(String) }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .idle:
                    idleView
                case .loading:
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .customers(list):
                    resultsScaffold(count: list.count) {
                        List(list) { c in
                            NavigationLink(value: CustomerRef(tenant: tenant ?? "",
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppBackground())
            .navigationTitle("Search")
            .navigationDestination(for: CustomerRef.self) { CustomerDetailScreen(session: session, ref: $0) }
            .toolbar { searchToolbar }
            .onChange(of: mode) { _, _ in phase = .idle; term = "" }
        }
        .searchable(text: $term, prompt: promptText)
        .onSubmit(of: .search) { Task { await run() } }
    }

    @ToolbarContentBuilder private var searchToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Search by", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
            .labelsHidden()
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Search", systemImage: "magnifyingglass") { Task { await run() } }
                .disabled(!canSearch)
                .help("Search")
        }
    }

    @ViewBuilder private var idleView: some View {
        if mode == .customer && tenant == nil {
            ContentUnavailableView {
                Label("Pick a Tenant", systemImage: "building.2")
            } description: {
                Text("Choose a tenant in the toolbar to search customers.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("Search", systemImage: "magnifyingglass")
            } description: {
                Text(idleHint)
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
        mode == .iccid ? "ICCID" : "Name, email, or phone"
    }

    private var idleHint: String {
        mode == .iccid
            ? "Enter a 19–20 digit ICCID starting with 89, then press Return or tap Search."
            : "Enter at least 3 characters, then press Return or tap Search."
    }

    private var canSearch: Bool {
        let t = term.trimmingCharacters(in: .whitespaces)
        return mode == .iccid ? !t.isEmpty : (t.count >= 3 && tenant != nil)
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
                    phase = .esim(e, resp.tenant ?? tenant ?? "")
                } else {
                    phase = .empty("No eSIM found for that ICCID.")
                }
            } else {
                guard let tn = tenant else { phase = .idle; return }
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
