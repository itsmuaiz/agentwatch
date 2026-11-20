import SwiftUI

struct AgentsView: View {
    @EnvironmentObject var model: WatchModel

    var body: some View {
        List {
            ForEach(model.agents) { agent in
                NavigationLink(destination: ChatView(agent: agent)) {
                    AgentRow(agent: agent)
                }
            }
            if model.agents.isEmpty {
                Text("No agents")
                    .foregroundColor(Theme.textMuted)
                    .font(.caption)
            }
        }
        .navigationTitle("Agents")
        .listStyle(.carousel)
        .refreshable {
            await model.reloadAgents()
        }
    }
}

struct AgentRow: View {
    let agent: Agent

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.providerColor(agent.provider))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.body.weight(.semibold))
                    .foregroundColor(Theme.textPrimary)
                Text(agent.provider.displayName)
                    .font(.caption2)
                    .foregroundColor(Theme.textSecond)
            }
            Spacer()
            if agent.pendingCount > 0 {
                Text("\(agent.pendingCount)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.waiting)
                    .clipShape(Capsule())
                    .foregroundColor(.white)
            }
            StatusDot(status: agent.status)
        }
        .padding(.vertical, 4)
    }
}

struct StatusDot: View {
    let status: AgentStatus
    var body: some View {
        Circle()
            .fill(Theme.statusColor(status))
            .frame(width: 6, height: 6)
    }
}
