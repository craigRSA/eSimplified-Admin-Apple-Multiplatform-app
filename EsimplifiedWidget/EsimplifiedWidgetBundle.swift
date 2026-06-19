import WidgetKit
import SwiftUI

@main
struct EsimplifiedWidgetBundle: WidgetBundle {
    var body: some Widget {
        RevenueWidget()
    }
}

struct RevenueWidget: Widget {
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
