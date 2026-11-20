import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var conn: ConnectionStore
    @EnvironmentObject var model: WatchModel
    @State private var ttsEnabled = Speaker.shared.enabled
    @State private var showDisconnect = false

    var body: some View {
        List {
            Section("Audio") {
                Toggle("Read replies aloud", isOn: $ttsEnabled)
                    .onChange(of: ttsEnabled) { v in Speaker.shared.enabled = v }
            }
            Section("Status") {
                HStack {
                    Text("Relay")
                    Spacer()
                    Circle()
                        .fill(model.isConnected ? Theme.approve : Theme.textMuted)
                        .frame(width: 8, height: 8)
                    Text(model.isConnected ? "Live" : "Offline")
                        .font(.caption)
                        .foregroundColor(model.isConnected ? Theme.approve : Theme.textMuted)
                }
                HStack {
                    Text("Pending")
                    Spacer()
                    Text("\(model.pendingApprovals.count)")
                        .foregroundColor(Theme.textSecond)
                }
            }
            Section {
                Button("Reconnect") {
                    model.stop()
                    model.startSSE()
                }
                .foregroundColor(Theme.waiting)

                Button("Disconnect") {
                    showDisconnect = true
                }
                .foregroundColor(Theme.decline)
            }
        }
        .navigationTitle("Settings")
        .alert("Disconnect?", isPresented: $showDisconnect) {
            Button("Disconnect", role: .destructive) {
                model.stop()
                conn.clear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the relay connection from this watch.")
        }
    }
}
