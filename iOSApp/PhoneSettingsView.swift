import SwiftUI

struct PhoneSettingsView: View {
    @EnvironmentObject var conn: ConnectionStore
    @EnvironmentObject var model: PhoneModel
    @State private var timeout = 300
    @State private var showDisconnect = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Approval timeout") {
                    Stepper("\(timeout / 60) min", value: $timeout, in: 60...3600, step: 60)
                    Button(saving ? "Saving…" : "Save timeout") {
                        saving = true
                        Task {
                            do { try await model.saveTimeout(timeout) }
                            catch { self.error = error.localizedDescription }
                            saving = false
                        }
                    }
                    .disabled(saving)
                }
                Section("Watch") {
                    Button("Send creds to watch again") {
                        guard let u = Keychain.get(.relayURL), let t = Keychain.get(.deviceToken) else { return }
                        Connectivity.shared.sendCreds(relayURL: u, token: t)
                    }
                }
                if let e = error {
                    Section { Text(e).foregroundColor(Theme.decline).font(.caption) }
                }
                Section {
                    Button("Disconnect", role: .destructive) { showDisconnect = true }
                }
                Section("Relay URL") {
                    if let url = Keychain.get(.relayURL) {
                        Text(url).font(.caption).foregroundColor(Theme.textSecond)
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear { timeout = model.settings?.timeoutSeconds ?? 300 }
            .alert("Disconnect?", isPresented: $showDisconnect) {
                Button("Disconnect", role: .destructive) { conn.clear() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the relay connection. The watch will also lose access on next open.")
            }
        }
    }
}
