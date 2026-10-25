import Foundation
import WatchConnectivity

/// Keeps the iPhone and Watch stores in step using the latest-state channel.
final class Connectivity: NSObject, WCSessionDelegate {
    static let shared = Connectivity()

    var onSnapshot: ((Snapshot) -> Void)?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ snapshot: Snapshot) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let data = try? JSONEncoder.pulse.encode(snapshot) else { return }
        var context: [String: Any] = ["snapshot": data]
        #if os(iOS)
        // Only the iPhone owns the sign-in. It shares the token with the paired Watch over the encrypted link.
        if let token = Keychain.get("pulse.token") { context["token"] = token }
        #endif
        try? WCSession.default.updateApplicationContext(context)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        #if os(watchOS)
        Keychain.set(applicationContext["token"] as? String, for: "pulse.token")
        #endif
        guard let data = applicationContext["snapshot"] as? Data,
              let snapshot = try? JSONDecoder.pulse.decode(Snapshot.self, from: data) else { return }
        DispatchQueue.main.async { self.onSnapshot?(snapshot) }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
