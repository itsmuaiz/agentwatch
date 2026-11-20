import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var conn: ConnectionStore
    @StateObject private var phoneModel = PhoneModel()

    var body: some View {
        TabView {
            PhoneAgentsView()
                .tabItem { Label("Agents", systemImage: "cpu") }
                .environmentObject(phoneModel)

            PhoneApprovalsView()
                .tabItem { Label("Approvals", systemImage: "checkmark.shield") }
                .environmentObject(phoneModel)

            RulesView()
                .tabItem { Label("Rules", systemImage: "slider.horizontal.3") }
                .environmentObject(phoneModel)

            AuditView()
                .tabItem { Label("Audit", systemImage: "list.bullet.rectangle") }
                .environmentObject(phoneModel)

            PhoneSettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .environmentObject(phoneModel)
        }
        .tint(Theme.waiting)
        .task { await phoneModel.reload() }
    }
}
