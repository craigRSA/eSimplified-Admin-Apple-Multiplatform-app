import SwiftUI
import EsimplifiedKit

enum AdminSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard, orders, customers, search, inventory, agentOrder, agentApprovals, profile
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
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
    @State private var showSetup2FA = false

    var body: some View {
        NavigationSplitView {
            List(model.sections, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage).tag(section)
            }
            .navigationTitle("eSimplified")
            .toolbar {
                Button("Log out") { model.logout() }
            }
        } detail: {
            switch selection {
            case .dashboard:
                if let session = model.session { DashboardScreen(session: session) }
            case .orders:
                if let session = model.session { OrdersScreen(session: session) }
            case .profile:
                ProfilePlaceholder(model: model, showSetup2FA: $showSetup2FA)
            case .some(let section):
                PlaceholderDetail(title: section.title)
            case nil:
                PlaceholderDetail(title: "Select a section")
            }
        }
        .sheet(isPresented: $showSetup2FA) {
            if let session = model.session {
                TwoFactorSetupView(host: session.host, accessToken: session.accessToken)
            }
        }
        .onAppear { if selection == nil { selection = model.sections.first } }
    }
}

private struct PlaceholderDetail: View {
    let title: String
    var body: some View {
        ContentUnavailableView(title, systemImage: "square.dashed",
                               description: Text("Coming in a later slice."))
            .navigationTitle(title)
    }
}

private struct ProfilePlaceholder: View {
    @Bindable var model: AdminAppModel
    @Binding var showSetup2FA: Bool
    var body: some View {
        Form {
            if let s = model.session {
                LabeledContent("Host", value: s.host)
                LabeledContent("Account", value: s.accountType)
            }
            Button("Set up two-factor authentication") { showSetup2FA = true }
        }
        .navigationTitle("Profile")
    }
}
