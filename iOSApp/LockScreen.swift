import SwiftUI

struct LockScreen: View {
    var onUnlock: () -> Void
    var error: String?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(Theme.waiting)
            Text("AgentWatch")
                .font(.title.bold())
            if let e = error {
                Text(e).font(.caption).foregroundColor(Theme.decline).multilineTextAlignment(.center)
            }
            Button("Unlock with Face ID / Passcode") { onUnlock() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.waiting)
            Spacer()
        }
        .padding()
        .background(Theme.background.ignoresSafeArea())
    }
}
