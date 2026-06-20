import AppIntents
import EsimplifiedKit

/// Includes the engine package's App Intents so Siri/Spotlight discover them.
struct EsimplifiedAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [EsimplifiedKitPackage.self] }
}

/// Voice phrases for the revenue intents. Every phrase must contain
/// `\(.applicationName)` so Siri can route it to this app.
struct EsimplifiedShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TodaysRevenueIntent(),
            phrases: [
                "What's today's revenue in \(.applicationName)",
                "Show today's revenue in \(.applicationName)",
                "How much did \(.applicationName) make today",
            ],
            shortTitle: "Today's Revenue",
            systemImageName: "dollarsign.circle"
        )
        AppShortcut(
            intent: YesterdayRevenueIntent(),
            phrases: [
                "What was yesterday's revenue in \(.applicationName)",
                "Show yesterday's revenue in \(.applicationName)",
            ],
            shortTitle: "Yesterday's Revenue",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: RevenueVsYesterdayIntent(),
            phrases: [
                "How is \(.applicationName) doing today",
                "Compare \(.applicationName) revenue to yesterday",
            ],
            shortTitle: "Revenue vs Yesterday",
            systemImageName: "chart.line.uptrend.xyaxis"
        )
    }
}
