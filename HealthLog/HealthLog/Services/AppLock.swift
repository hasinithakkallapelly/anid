import Foundation
import LocalAuthentication

enum AppLock {
    /// Face ID / Touch ID, falling back to the device passcode.
    static func authenticate() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode set on the device at all — nothing to lock with.
            return true
        }
        return (try? await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock your health log."
        )) ?? false
    }
}
