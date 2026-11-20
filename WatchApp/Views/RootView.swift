import SwiftUI

struct RootView: View {
    @EnvironmentObject var conn: ConnectionStore
    @EnvironmentObject var model: WatchModel

    var body: some View {
        if !conn.isConfigured {
            PairView()
        } else {
            TabView {
                AgentsView()
                ApprovalsView()
                SettingsView()
            }
            .tabViewStyle(.verticalPage)
            .onAppear {
                Task { await model.reloadAgents() }
            }
        }
    }
}
