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
            VStack(spacing: Spacing.md) {
                Picker("Search by", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack(spacing: Spacing.sm) {
                    TextField(promptText, text: $term)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(mode == .iccid ? .numberPad : .default)
                        #endif
                        .onSubmit { Task { await run() } }
                    Button("Search") { Task { await run() } }
                        .disabled(!canSearch)
                }

                resultArea
            }
            .padding(Spacing.lg)
            .background(AppBackground())
            .navigationTitle("Search")
            .navigationDestination(for: CustomerRef.self) { CustomerDetailScreen(session: session, ref: $0) }
            .onChange(of: mode) { _, _ in phase = .idle; term = "" }
        }
    }

    private var promptText: String {
        mode == .iccid ? "ICCID (starts with 89…)" : "Name, email, or phone"
    }
    private var canSearch: Bool {
        let t = term.trimmingCharacters(in: .whitespaces)
        // ICCID: any non-empty term (matches the web, which only checks for empty).
        return mode == .iccid ? !t.isEmpty : (t.count >= 3 && tenant != nil)
    }

    @ViewBuilder private var resultArea: some View {
        switch phase {
        case .idle:
            if mode == .customer && tenant == nil {
                ContentUnavailableView("Pick a tenant", systemImage: "building.2",
                                       description: Text("Choose a tenant in the toolbar to search customers."))
            } else {
                ContentUnavailableView("Search by \(mode.rawValue.lowercased())", systemImage: "magnifyingglass",
                                       description: Text(mode == .iccid ? "Enter an ICCID." : "Enter a name, email, or phone."))
            }
        case .loading:
            ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .customers(list):
            List(list) { c in
                NavigationLink(value: CustomerRef(tenant: tenant ?? "", customerId: c.customerId ?? c.id)) {
                    customerRow(c)
                }
            }
            .listStyle(.plain)
        case let .esim(esim, esimTenant):
            List {
                NavigationLink(value: CustomerRef(tenant: esimTenant,
                                                  customerId: esim.customer?.customerId ?? "",
                                                  iccid: esim.iccid)) {
                    esimRow(esim, esimTenant)
                }
            }
            .listStyle(.plain)
        case let .empty(message):
            ContentUnavailableView(message, systemImage: "magnifyingglass")
        case let .failed(message):
            ContentUnavailableView("Search failed", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
        }
    }

    private func customerRow(_ c: Customer) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs / 2) {
            Text(c.displayName).font(.headline)
            if let e = c.email, e != c.displayName { Text(e).font(.caption).foregroundStyle(.secondary) }
            if let p = c.phoneNumber, !p.isEmpty { Text(p).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func esimRow(_ e: EsimSummary, _ esimTenant: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs / 2) {
            Text(e.iccid).font(.headline.monospaced()).lineLimit(1)
            if let who = e.customer?.displayName { Text(who).font(.subheadline) }
            HStack(spacing: Spacing.sm) {
                if let cov = e.coverageName {
                    Label(cov, systemImage: "globe").font(.caption).foregroundStyle(.secondary)
                }
                if !esimTenant.isEmpty { Text(esimTenant).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }

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
            phase = .failed(adminErrorMessage(error))
        } catch is CancellationError {
        } catch {
            phase = .failed("Unexpected error.")
        }
    }
}
