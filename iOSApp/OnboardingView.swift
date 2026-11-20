import SwiftUI

/// First-run setup: relay URL + admin key → pair → save.
struct OnboardingView: View {
    @EnvironmentObject var conn: ConnectionStore
    @State private var relayURL = ""
    @State private var adminKey = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Relay") {
                    TextField("https://relay.example.com", text: $relayURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    SecureField("Admin key", text: $adminKey)
                }
                Section {
                    Button(working ? "Connecting…" : "Connect") { connect() }
                        .disabled(working || relayURL.isEmpty || adminKey.isEmpty)
                }
                if let e = error {
                    Section {
                        Text(e).foregroundColor(Theme.decline).font(.caption)
                    }
                }
                Section("About") {
                    Text("Your relay URL is printed when you start the backend (npm start). The admin key is printed once on first run.")
                        .font(.caption)
                        .foregroundColor(Theme.textSecond)
                }
            }
            .navigationTitle("Connect to relay")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func connect() {
        guard let url = URL(string: relayURL) else { error = "Invalid URL"; return }
        working = true; error = nil
        Task {
            do {
                let token = try await RelayClient.pair(baseURL: url, adminKey: adminKey)
                conn.save(relayURL: relayURL, token: token)
                // Push to watch
                Connectivity.shared.sendCreds(relayURL: relayURL, token: token)
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}
