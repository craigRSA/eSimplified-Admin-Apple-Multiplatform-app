import SwiftUI
import EsimplifiedKit

/// Identifies a customer to open in `CustomerDetailScreen`. Mirrors the web's
/// customer_details route params: tenant (schema), customer_id, optional iccid.
struct CustomerRef: Hashable {
    let tenant: String
    let customerId: String
    var iccid: String?
}

extension Order {
    /// A deep-link to this order's customer, when the order carries a customer id.
    var customerRef: CustomerRef? {
        guard let cid = customerId, !cid.isEmpty else { return nil }
        return CustomerRef(tenant: tenant, customerId: cid, iccid: iccid)
    }
}

/// Native version of the web `customer_details` page: profile, the customer's
/// eSIMs, and their order history.
struct CustomerDetailScreen: View {
    let session: Session
    let ref: CustomerRef

    @State private var phase: Phase = .loading
    enum Phase { case loading, loaded(Customer?, [EsimSummary], [Order]), failed(String) }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView("Couldn't load customer", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            case let .loaded(customer, esims, orders):
                content(customer, esims, orders)
            }
        }
        .navigationTitle("Customer")
        .background(AppBackground())
        .reload(on: ref.customerId) { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder private func content(_ customer: Customer?, _ esims: [EsimSummary], _ orders: [Order]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let customer { ProfileCard(customer: customer) }

                SectionCard(title: "eSIMs (\(esims.count))") {
                    if esims.isEmpty {
                        Text("No eSIMs assigned.").font(.callout).foregroundStyle(.secondary)
                    } else {
                        ForEach(esims) { e in
                            HStack {
                                Image(systemName: "simcard").foregroundStyle(.secondary)
                                Text(e.iccid).font(.callout.monospaced()).lineLimit(1)
                                Spacer()
                                if let cov = e.coverageName { Text(cov).font(.caption).foregroundStyle(.secondary) }
                                if e.iccid == ref.iccid {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).font(.caption)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                SectionCard(title: "Recent orders (\(orders.count))") {
                    if orders.isEmpty {
                        Text("No orders.").font(.callout).foregroundStyle(.secondary)
                    } else {
                        ForEach(orders) { o in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(o.packageName.isEmpty ? o.orderNumber : o.packageName)
                                        .font(.subheadline.weight(.medium)).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(o.usdPriceDisplay).font(.subheadline.monospacedDigit())
                                }
                                HStack(spacing: 6) {
                                    StatusBadge(status: o.paymentStatus)
                                    if !o.orderType.isEmpty {
                                        Text(o.orderType).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(shortDate(o.purchaseDate)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                            if o.id != orders.last?.id { Divider() }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func load() async {
        do {
            let client = LiveAPIClient(host: session.host, accessToken: session.accessToken)
            let q = ["customer__customer_id": ref.customerId, "limit": "10"]
            let cust = try await client.get("/api/customers/\(ref.tenant)/\(ref.customerId)/", query: [:],
                                            as: SingleCustomerResponse.self)
            let esims = (try? await client.get("/api/esims/\(ref.tenant)/", query: q, as: AssignedEsimsPage.self))?.esims ?? []
            let orders = (try? await client.get("/api/orders/\(ref.tenant)/", query: q, as: OrdersPage.self))?.orders ?? []
            phase = .loaded(cust.customer, esims, orders)
        } catch let error as APIError {
            phase = .failed(adminErrorMessage(error))
        } catch is CancellationError {
        } catch {
            phase = .failed("Unexpected error.")
        }
    }
}

private struct ProfileCard: View {
    let customer: Customer
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(customer.displayName).font(.title2.weight(.semibold))
            HStack(spacing: 8) {
                Badge(text: customer.isActive ? "Active" : "Disabled",
                      color: customer.isActive ? .green : .red)
                if customer.email != nil {
                    Badge(text: customer.emailVerified ? "Email verified" : "Email not verified",
                          color: customer.emailVerified ? .green : .orange)
                }
            }
            if let email = customer.email { Field(label: "Email", value: email) }
            if let phone = customer.phoneNumber, !phone.isEmpty { Field(label: "Phone", value: phone) }
            if let cid = customer.customerId { Field(label: "Customer ID", value: cid) }
            if let created = customer.created { Field(label: "Created", value: shortDate(created)) }
        }
        .glassCard()
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
        }
        .glassCard()
    }
}

private struct Field: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.callout).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }
}

private struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
