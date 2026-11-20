import SwiftUI

struct PhoneApprovalsView: View {
    @EnvironmentObject var model: PhoneModel
    @State private var filter: ApprovalStatus? = .pending
    @State private var selectedId: String?

    private var filtered: [Approval] {
        guard let f = filter else { return model.approvals }
        return model.approvals.filter { $0.status == f }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Status", selection: $filter) {
                    Text("All").tag(ApprovalStatus?.none)
                    Text("Pending").tag(ApprovalStatus?.some(.pending))
                    Text("Approved").tag(ApprovalStatus?.some(.approved))
                    Text("Declined").tag(ApprovalStatus?.some(.declined))
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                ForEach(filtered) { a in
                    NavigationLink(destination: PhoneApprovalDetailView(approvalId: a.id)) {
                        PhoneApprovalRow(approval: a)
                    }
                }
                if filtered.isEmpty {
                    Text("Nothing here.")
                        .foregroundColor(Theme.textMuted)
                        .font(.caption)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Approvals")
            .refreshable { await model.reload() }
        }
    }
}

struct PhoneApprovalRow: View {
    let approval: Approval

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Theme.riskColor(approval.risk))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(approval.title).font(.body)
                Text(approval.agentName + " · " + approval.actionType.displayName)
                    .font(.caption)
                    .foregroundColor(Theme.textSecond)
            }
            Spacer()
            statusIcon(approval.status)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    func statusIcon(_ s: ApprovalStatus) -> some View {
        switch s {
        case .pending:
            Image(systemName: "clock").foregroundColor(Theme.waiting)
        case .approved:
            Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.approve)
        case .declined:
            Image(systemName: "xmark.circle.fill").foregroundColor(Theme.decline)
        case .expired:
            Image(systemName: "timer").foregroundColor(Theme.textMuted)
        }
    }
}

// MARK: - Approval detail (phone)

struct PhoneApprovalDetailView: View {
    let approvalId: String
    @EnvironmentObject var model: PhoneModel
    @Environment(\.dismiss) var dismiss

    @State private var detail: ApprovalDetail?
    @State private var loading = true
    @State private var error: String?
    @State private var deciding = false
    @State private var decided = false
    @State private var declineReason = ""
    @State private var showDeclineAlert = false

    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else if let d = detail {
                Form {
                    Section("Request") {
                        LabeledContent("Agent", value: d.agentName)
                        LabeledContent("Action", value: d.actionType.displayName)
                        LabeledContent("Risk", value: d.risk.rawValue.capitalized)
                        LabeledContent("Title", value: d.title)
                    }
                    if !d.details.isEmpty {
                        Section("Details") {
                            ForEach(d.details.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                                LabeledContent(k, value: v)
                            }
                        }
                    }
                    Section("Why") {
                        Text(d.reasoning).font(.caption)
                    }
                    if d.status == .pending, d.sig != nil, !decided {
                        Section {
                            Button("Approve") {
                                guard let sig = d.sig else { return }
                                Task { try? await model.decide(approvalId: d.id, sig: sig, decision: "approved"); decided = true }
                            }
                            .foregroundColor(Theme.approve)

                            Button("Decline…") { showDeclineAlert = true }
                                .foregroundColor(Theme.decline)
                        }
                    } else if decided {
                        Section { Text("Done ✓").foregroundColor(Theme.textSecond) }
                    } else {
                        Section { Text(d.status.rawValue.capitalized).foregroundColor(Theme.textSecond) }
                    }
                }
                .alert("Decline reason (optional)", isPresented: $showDeclineAlert) {
                    TextField("Reason", text: $declineReason)
                    Button("Decline", role: .destructive) {
                        guard let sig = d.sig else { return }
                        Task {
                            try? await model.decide(approvalId: d.id, sig: sig, decision: "declined",
                                                    reason: declineReason.isEmpty ? nil : declineReason)
                            decided = true
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            } else {
                Text(error ?? "Not found").foregroundColor(Theme.textMuted)
            }
        }
        .navigationTitle("Approval")
        .task {
            guard let client = ConnectionStore.shared.client else { loading = false; return }
            do { detail = try await client.approvalDetail(id: approvalId) }
            catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}
