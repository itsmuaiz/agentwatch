import SwiftUI

struct ApprovalsView: View {
    @EnvironmentObject var model: WatchModel
    @State private var tab: ApprovalTab = .pending

    enum ApprovalTab: String, CaseIterable {
        case pending = "Pending"
        case history = "History"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segment tabs
            Picker("", selection: $tab) {
                ForEach(ApprovalTab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 4)
            .padding(.top, 4)

            List {
                let items = tab == .pending ? model.pendingApprovals : model.approvalHistory
                ForEach(items) { approval in
                    NavigationLink(destination: ApprovalDetailView(approvalId: approval.id)) {
                        ApprovalRow(approval: approval)
                    }
                }
                if (tab == .pending ? model.pendingApprovals : model.approvalHistory).isEmpty {
                    Text(tab == .pending ? "No pending approvals" : "No history")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                }
            }
            .listStyle(.carousel)
        }
        .navigationTitle("Approvals")
        .background(Theme.background)
    }
}

struct ApprovalRow: View {
    let approval: Approval

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                RiskBadge(risk: approval.risk)
                Spacer()
                if approval.status == .pending, let exp = approval.expiresAt {
                    ExpiryTimer(expiresAt: exp)
                }
            }
            Text(approval.title)
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(2)
            Text(approval.agentName)
                .font(.caption2)
                .foregroundColor(Theme.textSecond)
        }
        .padding(.vertical, 4)
    }
}

struct RiskBadge: View {
    let risk: Risk
    var body: some View {
        Text(risk.rawValue.capitalized)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.riskColor(risk).opacity(0.25))
            .foregroundColor(Theme.riskColor(risk))
            .clipShape(Capsule())
    }
}

struct ExpiryTimer: View {
    let expiresAt: Date
    @State private var remaining: TimeInterval = 0

    var body: some View {
        Text(formatRemaining(remaining))
            .font(.caption2.monospacedDigit())
            .foregroundColor(remaining < 60 ? Theme.decline : Theme.textMuted)
            .onAppear { tick() }
    }

    private func tick() {
        remaining = max(0, expiresAt.timeIntervalSinceNow)
        if remaining > 0 {
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                tick()
            }
        }
    }

    private func formatRemaining(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
