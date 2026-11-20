import SwiftUI

struct PhoneAgentsView: View {
    @EnvironmentObject var model: PhoneModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.agents) { agent in
                    NavigationLink(destination: PhoneChatView(agent: agent)) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Theme.providerColor(agent.provider))
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.name).font(.body.weight(.semibold))
                                Text(agent.provider.displayName)
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecond)
                            }
                            Spacer()
                            if agent.pendingCount > 0 {
                                Text("\(agent.pendingCount)")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(Theme.waiting)
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                            }
                            Circle()
                                .fill(Theme.statusColor(agent.status))
                                .frame(width: 8, height: 8)
                        }
                        .padding(.vertical, 4)
                    }
                }
                if model.agents.isEmpty && !model.isLoading {
                    Text("No agents on the relay.")
                        .foregroundColor(Theme.textMuted)
                        .font(.caption)
                }
            }
            .navigationTitle("Agents")
            .refreshable { await model.reload() }
            .overlay {
                if model.isLoading { ProgressView() }
            }
        }
    }
}
