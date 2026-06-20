import Foundation

/// Pure policy for the biometric app-lock: decide whether returning to the
/// foreground should re-lock, given when the app was backgrounded and the grace
/// window. Kept here (not in the app) so it has real unit tests.
public enum BiometricGate {
    public static func shouldRelock(backgroundedAt: Date?, now: Date, grace: TimeInterval) -> Bool {
        guard let backgroundedAt else { return false }
        return now.timeIntervalSince(backgroundedAt) > grace
    }
}
