import SwiftUI
import WatchKit
import UserNotifications
import BackgroundTasks

@main
struct AgentWatchApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(WatchModel.shared)
                .environmentObject(ConnectionStore.shared)
        }
        // Background refresh for approvals polling when foreground SSE is not running
        .backgroundTask(.appRefresh("poll")) {
            await WatchModel.shared.backgroundRefresh()
        }
    }
}

final class AppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        _ = Connectivity.shared   // activate WCSession
        WatchModel.shared.start() // start SSE + notification setup
    }
}
