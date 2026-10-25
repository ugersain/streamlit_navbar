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
        try? WCSession.default.updateApplicationContext(["snapshot": data])
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["snapshot"] as? Data,
              let snapshot = try? JSONDecoder.pulse.decode(Snapshot.self, from: data) else { return }
        DispatchQueue.main.async { self.onSnapshot?(snapshot) }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
