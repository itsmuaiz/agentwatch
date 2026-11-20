import SwiftUI
import LocalAuthentication

@main
struct AgentWatchiOSApp: App {
    @StateObject private var conn = ConnectionStore.shared
    @State private var unlocked = false
    @State private var authError: String?

    var body: some Scene {
        WindowGroup {
            if conn.isConfigured {
                if unlocked {
                    MainTabView()
                        .environmentObject(conn)
                } else {
                    LockScreen(onUnlock: { unlocked = true }, error: authError)
                        .onAppear { authenticate() }
                }
            } else {
                OnboardingView()
                    .environmentObject(conn)
            }
        }
    }

    private func authenticate() {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            unlocked = true; return   // no auth available, skip gate
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Open AgentWatch") { ok, e in
            DispatchQueue.main.async {
                if ok { unlocked = true }
                else { authError = e?.localizedDescription }
            }
        }
    }
}
