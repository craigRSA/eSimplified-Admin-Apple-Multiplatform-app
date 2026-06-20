import SwiftUI
import EsimplifiedKit

struct InventoryScreen: View {
    let session: Session

    @State private var phase: Phase = .loading

    enum Phase { case loading, loaded(Inventory), failed(String) }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView("Couldn't load inventory", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            case let .loaded(inv):
                content(inv)
            }
        }
        .navigationTitle("Inventory")
        .reload(on: 0) { await load() }
        .refreshable { await load() }
        .autoRefresh { await load() }
    }

    @ViewBuilder private func content(_ inv: Inventory) -> some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    InventoryStat(title: "Total eSIMs", value: inv.totalEsims, tint: .blue)
                    InventoryStat(title: "Assigned", value: inv.totalAssigned, tint: .green)
                    InventoryStat(title: "Unassigned", value: inv.totalUnassigned, tint: .orange)
                    InventoryStat(title: "Pending", value: inv.totalPending, tint: .yellow)
                }
                .padding(.vertical, 4)
            }
            if !inv.imsis.isEmpty {
                Section("By IMSI") {
                    ForEach(inv.imsis) { entry in
                        HStack {
                            Text(entry.imsi).font(.body.monospaced())
                            Spacer()
                            Text("\(entry.assignedCount) / \(entry.unassignedCount) / \(entry.pendingCount)")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        do {
            let client = LiveAPIClient(host: session.host, accessToken: session.accessToken)
            let inv = try await client.get("/api/inventory/", query: [:], as: Inventory.self)
            phase = .loaded(inv)
        } catch let error as APIError {
            phase = .failed(adminErrorMessage(error))
        } catch is CancellationError {
            // View navigated away mid-load — not a real error.
        } catch {
            phase = .failed("Unexpected error.")
        }
    }
}

private struct InventoryStat: View {
    let title: String
    let value: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value.formatted()).font(.title2.weight(.semibold)).foregroundStyle(tint)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}
