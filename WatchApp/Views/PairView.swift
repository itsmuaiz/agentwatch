import SwiftUI

/// Shown when no relay creds are stored. Two paths:
///  1. Automatic: phone pushes creds via WatchConnectivity (user opens iPhone app first).
///  2. Manual:    user types the 8-char pairing code from `npm run pair`.
struct PairView: View {
    @EnvironmentObject var conn: ConnectionStore
    @State private var mode: PairMode = .waiting

    enum PairMode { case waiting, manual }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.largeTitle)
                .foregroundColor(Theme.waiting)

            Text("AgentWatch")
                .font(.headline)
            Text("Open the iPhone app\nto connect automatically,\nor enter a pairing code.")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundColor(Theme.textSecond)

            Button("Enter code") { mode = .manual }
                .buttonStyle(.borderedProminent)
                .tint(Theme.waiting)
        }
        .padding()
        .background(Theme.background)
        .sheet(isPresented: .constant(mode == .manual)) {
            CodeEntryView(onDismiss: { mode = .waiting })
        }
    }
}

// MARK: - Manual code entry

struct CodeEntryView: View {
    var onDismiss: () -> Void
    @EnvironmentObject var conn: ConnectionStore

    @State private var relayURL = ""
    @State private var code = ""
    @State private var working = false
    @State private var errorMsg: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Pairing code")
                    .font(.caption.bold())
                    .foregroundColor(Theme.textSecond)

                TextField("https://relay.example.com", text: $relayURL)
                    .autocorrectionDisabled()
                    .font(.caption)

                TextField("XXXX-XXXX", text: $code)
                    .autocorrectionDisabled()
                    .font(.body.monospacedDigit())

                if let e = errorMsg {
                    Text(e).font(.caption2).foregroundColor(Theme.decline)
                }

                Button(working ? "Connecting…" : "Connect") {
                    guard !relayURL.isEmpty, !code.isEmpty else { return }
                    connect()
                }
                .disabled(working || relayURL.isEmpty || code.isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(Theme.waiting)

                Button("Cancel") { onDismiss() }
                    .foregroundColor(Theme.textMuted)
                    .buttonStyle(.plain)
            }
            .padding()
        }
        .background(Theme.surface)
    }

    private func connect() {
        guard let url = URL(string: relayURL) else {
            errorMsg = "Invalid URL"; return
        }
        working = true
        errorMsg = nil
        Task {
            do {
                let token = try await RelayClient.redeemCode(baseURL: url, code: code)
                conn.save(relayURL: relayURL, token: token)
                onDismiss()
            } catch {
                errorMsg = error.localizedDescription
            }
            working = false
        }
    }
}
