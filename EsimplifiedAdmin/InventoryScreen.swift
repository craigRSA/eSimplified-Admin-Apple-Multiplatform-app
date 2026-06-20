import SwiftUI
import EsimplifiedKit

struct InventoryScreen: View {
    let session: Session

    @Environment(\.tokenProvider) private var tokenProvider
    @State private var phase: Phase = .loading

    enum Phase { case loading, loaded(Inventory), failed(String) }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                loadingState
            case let .failed(message):
                ContentUnavailableView {
                    Label("Couldn't load inventory", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                        .buttonStyle(.glassProminent)
                }
            case let .loaded(inv):
                content(inv)
            }
        }
        .background(AppBackground())
        .navigationTitle("Inventory")
        .reload(on: 0) { await load() }
        .refreshable { await load() }
        .autoRefresh { await load() }
        .refreshCommand { Task { await load() } }
    }

    /// Skeleton tiles instead of a bare spinner so the grid doesn't pop in.
    private var loadingState: some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Spacing.md)], spacing: Spacing.md) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            SkeletonBar(width: 56, height: 22)
                            SkeletonBar(width: 88, height: 12)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(radius: Radius.chip, padding: Spacing.md)
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder private func content(_ inv: Inventory) -> some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Spacing.md)], spacing: Spacing.md) {
                    InventoryStat(title: "Total eSIMs", value: inv.totalEsims, systemImage: "simcard.2")
                    InventoryStat(title: "Assigned", value: inv.totalAssigned, systemImage: "person.fill.checkmark")
                    InventoryStat(title: "Unassigned", value: inv.totalUnassigned, systemImage: "tray")
                    InventoryStat(title: "Pending", value: inv.totalPending, systemImage: "clock")
                }
                .padding(.vertical, Spacing.xs)
            }
            .listRowSeparator(.hidden)
            if !inv.imsis.isEmpty {
                Section {
                    // Column key so the three figures aren't a cryptic "X / Y / Z".
                    HStack(spacing: Spacing.sm) {
                        Text("IMSI").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Assigned").frame(maxWidth: .infinity, alignment: .trailing)
                        Text("Unassigned").frame(maxWidth: .infinity, alignment: .trailing)
                        Text("Pending").frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
                    .accessibilityHidden(true)

                    ForEach(inv.imsis) { entry in
                        HStack(spacing: Spacing.sm) {
                            Text(entry.imsi).font(.callout.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(entry.assignedCount.formatted())
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(entry.unassignedCount.formatted())
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(entry.pendingCount.formatted())
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .foregroundStyle(entry.pendingCount > 0 ? Color.warning : Color.secondary)
                        }
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("IMSI \(entry.imsi): \(entry.assignedCount) assigned, \(entry.unassignedCount) unassigned, \(entry.pendingCount) pending")
                    }
                } header: { Text("By IMSI") }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func load() async {
        do {
            let client = LiveAPIClient(host: session.host, tokenProvider: tokenProvider)
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
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // The glyph is quiet (.secondary) so the figure leads; the icon
            // identifies the metric without leaning on a pastel color.
            Image(systemName: systemImage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(value.formatted()).font(.title2.weight(.semibold))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: Radius.chip, padding: Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value.formatted())")
    }
}
