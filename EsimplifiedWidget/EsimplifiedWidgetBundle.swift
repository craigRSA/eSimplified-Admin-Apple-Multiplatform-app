import WidgetKit
import SwiftUI

@main
struct EsimplifiedWidgetBundle: WidgetBundle {
    var body: some Widget {
        RevenueWidget()
    }
}

struct RevenueWidget: Widget {
    // Frozen identity — WidgetKit keys installed widget instances by `kind`, so
    // changing it orphans every placed widget. The "glance" namespace is historical
    // (the app's former name); do not "fix" it.
    private let kind = "io.esimplified.glance.RevenueWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RevenueProvider()) { entry in
            RevenueWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Today's Revenue")
        .description("Consolidated eSimplified revenue today, with the change vs yesterday.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
