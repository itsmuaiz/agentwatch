import Foundation
import WatchConnectivity

/// WatchConnectivity bridge: phone sends relay URL + token to watch via applicationContext.
/// Both sides import this file; the platform guards select the right behaviour.
public final class Connectivity: NSObject, WCSessionDelegate, ObservableObject {
    public static let shared = Connectivity()

    @Published public private(set) var reachable = false

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Phone → watch: send creds

#if os(iOS)
    public func sendCreds(relayURL: String, token: String) {
        guard WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        try? WCSession.default.updateApplicationContext([
            "relay_url": relayURL,
            "token": token,
        ])
    }
#endif

    // MARK: - WCSessionDelegate

    public func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.reachable = session.isReachable }
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.reachable = session.isReachable }
    }

    // Watch receives creds from phone
    public func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let url   = context["relay_url"] as? String,
              let token = context["token"]     as? String else { return }
        DispatchQueue.main.async {
            Task { @MainActor in
                ConnectionStore.shared.save(relayURL: url, token: token)
            }
        }
    }

#if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
#endif
}
