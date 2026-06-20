import SwiftUI
import EsimplifiedKit

enum AdminSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard, orders, customers, search, inventory, agentOrder, agentApprovals, profile
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Overview"
        case .orders: "Order History"
        case .customers: "Customers"
        case .search: "Search"
        case .inventory: "Inventory"
        case .agentOrder: "Agent Order"
        case .agentApprovals: "Agent Approvals"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "chart.bar"
        case .orders: "list.bullet.rectangle"
        case .customers: "person.2"
        case .search: "magnifyingglass"
        case .inventory: "shippingbox"
        case .agentOrder: "cart.badge.plus"
        case .agentApprovals: "checkmark.seal"
        case .profile: "person.crop.circle"
        }
    }

    /// Backend scope resource gating this section; nil = always shown.
    var scopeResource: String? {
        switch self {
        case .dashboard: "statistics"
        case .orders: "order"
        case .customers: "customer"
        case .search: "search"
        case .inventory: "inventory"
        case .agentOrder: "agent_order"
        case .agentApprovals: "agent_approval"
        case .profile: nil
        }
    }
}

struct AdminShell: View {
    @Bindable var model: AdminAppModel
    @State private var selection: AdminSection?
    @AppStorage("autoRefreshSeconds") private var autoRefreshSeconds = 0

    var body: some View {
        NavigationSplitView {
            List(model.sections, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage).tag(section)
            }
            .navigationTitle("eSimplified")
        } detail: {
            detail
                .toolbar {
                    ToolbarItem(placement: .principal) { UTCClock() }
                    ToolbarItemGroup(placement: .primaryAction) {
                        if !model.tenants.isEmpty { TenantMenu(model: model) }
                        RefreshIntervalMenu(seconds: $autoRefreshSeconds)
                    }
                }
        }
        .task { await model.loadTenants() }
        .onAppear { if selection == nil { selection = model.sections.first } }
    }

    @ViewBuilder private var detail: some View {
        let scope = model.tenantScope
        switch selection {
        case .dashboard:
            if let session = model.session { DashboardScreen(session: session, tenant: scope) }
        case .orders:
            if let session = model.session { OrdersScreen(session: session, tenant: scope) }
        case .customers:
            if let session = model.session { CustomersScreen(session: session, tenant: scope) }
        case .inventory:
            if let session = model.session { InventoryScreen(session: session) }
        case .search:
            if let session = model.session { SearchScreen(session: session, tenant: scope) }
        case .agentApprovals:
            if let session = model.session { AgentApprovalsScreen(session: session, tenant: scope) }
        case .profile:
            if let session = model.session { ProfileScreen(session: session, onLogout: { model.logout() }) }
        case .some(let section):
            PlaceholderDetail(title: section.title)
        case nil:
            PlaceholderDetail(title: "Select a section")
        }
    }
}

/// Tenant scope picker, rendered icon-only so it sits cleanly beside the
/// auto-refresh control in the toolbar. Filled icon = a specific tenant is
/// selected; outline = all tenants.
private struct TenantMenu: View {
    let model: AdminAppModel
    var body: some View {
        Menu {
            Button { model.selectedTenant = nil } label: {
                Label("All Tenants", systemImage: model.selectedTenant == nil ? "checkmark" : "building.2")
            }
            Divider()
            ForEach(model.tenants) { tenant in
                Button { model.selectedTenant = tenant } label: {
                    Label(tenant.name, systemImage: model.selectedTenant?.id == tenant.id ? "checkmark" : "building.2")
                }
            }
        } label: {
            Label(model.selectedTenant?.name ?? "All Tenants",
                  systemImage: model.selectedTenant == nil ? "building.2" : "building.2.fill")
                .labelStyle(.iconOnly)
        }
        .help(model.selectedTenant?.name ?? "All Tenants")
    }
}

private struct PlaceholderDetail: View {
    let title: String
    var body: some View {
        ContentUnavailableView(title, systemImage: "square.dashed",
                               description: Text("Coming soon."))
            .navigationTitle(title)
    }
}
