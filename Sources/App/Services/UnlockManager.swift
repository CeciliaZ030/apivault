import Foundation
import LocalAuthentication

@MainActor
final class UnlockManager: ObservableObject {
    @Published private(set) var unlockState: UnlockState = .locked

    var isUnlocked: Bool {
        unlockState == .unlockedSession
    }

    func lock() {
        unlockState = .locked
    }

    func unlock() async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? NSError(domain: "UnlockManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "This Mac cannot evaluate device owner authentication."])
        }

        let reason = "Unlock Apivault to reveal or copy secrets."
        let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        unlockState = success ? .unlockedSession : .locked
    }
}
