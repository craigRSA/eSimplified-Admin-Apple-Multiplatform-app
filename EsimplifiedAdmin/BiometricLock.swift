#if os(iOS)
import SwiftUI
import LocalAuthentication
import EsimplifiedKit

/// Resolves the device's actual biometry flavour at runtime so copy and icons
/// match (Face ID on modern iPhones, Touch ID on home-button iPads/iPhones,
/// Optic ID on Apple Vision Pro, fallback for devices without biometrics).
struct BiometryKind {
    let label: String       // "Face ID" / "Touch ID" / "Optic ID" / "biometrics"
    let systemImage: String // "faceid" / "touchid" / "opticid" / "lock"
    static var current: BiometryKind {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) // REQUIRED: populates biometryType
        switch ctx.biometryType {
        case .faceID:  return .init(label: "Face ID",  systemImage: "faceid")
        case .touchID: return .init(label: "Touch ID", systemImage: "touchid")
        case .opticID: return .init(label: "Optic ID", systemImage: "opticid")
        default:       return .init(label: "biometrics", systemImage: "lock")
        }
    }
    /// Lazily initialised once per process — biometry type never changes at runtime.
    static let cached: BiometryKind = .current
}

/// Abstracts LocalAuthentication so the controller is testable and the policy
/// choice is centralized. Uses `.deviceOwnerAuthentication` (biometrics WITH
/// passcode fallback) — required so a biometric lockout can recover via passcode.
protocol BiometricAuthenticator {
    func canEvaluate() -> Bool
    func evaluate(reason: String) async -> Bool
}

struct LAContextAuthenticator: BiometricAuthenticator {
    func canEvaluate() -> Bool {
        // canEvaluatePolicy's result is volatile — checked fresh each call, never stored.
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }
    func evaluate(reason: String) async -> Bool {
        let context = LAContext()   // fresh context per evaluation
        do { return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) }
        catch { return false }
    }
}

/// Drives the iOS app-lock. Purely a UI gate — never touches the session/token,
/// so refresh keeps running underneath. `isLocked` overlays the lock screen.
@Observable
@MainActor
final class AppLockController {
    private(set) var isLocked = false
    var isInactive = false      // drives the privacy cover in the app switcher
    private var backgroundedAt: Date?
    private var authenticating = false

    private let grace: TimeInterval
    private let authenticator: BiometricAuthenticator
    /// Whether the lock is in force (biometric sign-in enabled & device capable).
    var isEnabled: () -> Bool

    init(grace: TimeInterval = 180,
         authenticator: BiometricAuthenticator = LAContextAuthenticator(),
         isEnabled: @escaping () -> Bool) {
        self.grace = grace
        self.authenticator = authenticator
        self.isEnabled = isEnabled
    }

    /// Call once when a signed-in shell first appears (cold launch).
    func lockOnLaunch() {
        guard isEnabled() else { isLocked = false; return }
        isLocked = true
    }

    func willResignActive() {
        isInactive = true
        if backgroundedAt == nil { backgroundedAt = Date() }
    }

    func didBecomeActive() {
        isInactive = false
        guard isEnabled() else { isLocked = false; backgroundedAt = nil; return }
        if BiometricGate.shouldRelock(backgroundedAt: backgroundedAt, now: Date(), grace: grace) {
            isLocked = true
        }
        backgroundedAt = nil
    }

    func authenticate() async {
        guard isLocked, !authenticating else { return }
        // Fail CLOSED: if the device can't evaluate (e.g. the passcode was removed),
        // stay locked rather than expose revenue/PII on a finance admin app. The
        // "Use password instead" button (→ sign out) is the recoverable path, so the
        // user is never permanently trapped.
        guard authenticator.canEvaluate() else { return }
        authenticating = true; defer { authenticating = false }
        if await authenticator.evaluate(reason: "Unlock eSimplified Admin") {
            isLocked = false
        }
    }
}

/// Full-screen lock UI: auto-prompts biometrics, retry on failure, and a password
/// escape hatch that signs out (drops to the login screen).
struct LockScreen: View {
    let controller: AppLockController
    var onUsePassword: () -> Void

    var body: some View {
        let kind = BiometryKind.cached
        ZStack {
            AppBackground()
            VStack(spacing: Spacing.lg) {
                Image(systemName: kind.systemImage).font(.system(size: 56)).foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text("eSimplified Admin").font(.title2.weight(.semibold))
                Text("Locked").font(.subheadline).foregroundStyle(.secondary)
                Button("Unlock") { Task { await controller.authenticate() } }
                    .buttonStyle(.glassProminent).controlSize(.large)
                Button("Use password instead", action: onUsePassword)
                    .buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)
            }
            .padding(Spacing.xxl)
        }
        .task { await controller.authenticate() }   // auto-prompt on appear
    }
}

/// Opaque privacy cover shown while the app is inactive/backgrounded, so revenue
/// figures don't appear in the iOS app-switcher snapshot.
private struct PrivacyCover: View {
    var body: some View {
        ZStack { AppBackground(); Image("LogoWordmark").resizable().scaledToFit().frame(maxWidth: 180, maxHeight: 48) }
    }
}

/// Wraps the signed-in shell with the lock + privacy overlays and scene-phase wiring.
struct LockContainer: ViewModifier {
    let controller: AppLockController
    var onUsePassword: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .overlay { if controller.isLocked { LockScreen(controller: controller, onUsePassword: onUsePassword) } }
            .overlay { if controller.isInactive && !controller.isLocked { PrivacyCover() } }
            .onAppear { controller.lockOnLaunch() }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active: controller.didBecomeActive()
                case .inactive, .background: controller.willResignActive()
                @unknown default: break
                }
            }
    }
}
#endif
