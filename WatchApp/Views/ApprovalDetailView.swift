import SwiftUI

struct ApprovalDetailView: View {
    let approvalId: String
    @EnvironmentObject var model: WatchModel
    @Environment(\.dismiss) var dismiss

    @State private var detail: ApprovalDetail?
    @State private var loading = true
    @State private var error: String?
    @State private var showDeclineSheet = false
    @State private var showHighRiskConfirm = false
    @State private var pendingDecision: String?
    @State private var deciding = false
    @State private var decided = false

    var body: some View {
        Group {
            if loading {
                ProgressView().tint(Theme.waiting)
            } else if let d = detail {
                approvalBody(d)
            } else {
                Text(error ?? "Not found")
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
            }
        }
        .navigationTitle("Approval")
        .background(Theme.background)
        .task { await load() }
        .sheet(isPresented: $showDeclineSheet) {
            DeclineReasonSheet { reason in
                showDeclineSheet = false
                guard let d = detail, let sig = d.sig else { return }
                doDecide(id: d.id, sig: sig, decision: "declined", reason: reason.isEmpty ? nil : reason)
            }
        }
    }

    // MARK: - Body

    @ViewBuilder
    private func approvalBody(_ d: ApprovalDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    HStack { RiskBadge(risk: d.risk); Spacer() }
                    Text(d.title)
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                    Text(d.agentName + " · " + d.actionType.displayName)
                        .font(.caption2)
                        .foregroundColor(Theme.textSecond)
                }

                // Details grid
                if !d.details.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(d.details.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                            HStack(alignment: .top) {
                                Text(k + ":").font(.caption2).foregroundColor(Theme.textSecond).frame(width: 70, alignment: .leading)
                                Text(v).font(.caption2).foregroundColor(Theme.textPrimary)
                            }
                        }
                    }
                    .padding(8)
                    .background(Theme.surface)
                    .cornerRadius(10)
                }

                // Why?
                VStack(alignment: .leading, spacing: 4) {
                    Text("Why?").font(.caption2.bold()).foregroundColor(Theme.textSecond)
                    Text(d.reasoning).font(.caption2).foregroundColor(Theme.textPrimary)
                }

                if decided {
                    Text("Decision sent ✓")
                        .font(.caption.bold())
                        .foregroundColor(Theme.textSecond)
                        .frame(maxWidth: .infinity)
                } else if d.status == .pending, d.sig != nil {
                    // High risk: show confirm step
                    if d.risk == .high, let pending = pendingDecision, pending == "approved", !showHighRiskConfirm {
                        // This state is reached after first tap; we redirect to confirm
                        EmptyView()
                    } else {
                        actionButtons(d)
                    }
                } else if d.status != .pending {
                    Text(d.status.rawValue.capitalized)
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        // High-risk confirm overlay
        .alert("Confirm Approve?", isPresented: $showHighRiskConfirm) {
            Button("Yes, approve", role: .destructive) {
                guard let d = detail, let sig = d.sig else { return }
                doDecide(id: d.id, sig: sig, decision: "approved", confirmed: true)
            }
            Button("Cancel", role: .cancel) { pendingDecision = nil }
        } message: {
            Text("This is a high-risk action. Approve?")
        }
    }

    @ViewBuilder
    private func actionButtons(_ d: ApprovalDetail) -> some View {
        VStack(spacing: 8) {
            // Approve
            Button {
                if d.risk == .high {
                    pendingDecision = "approved"
                    showHighRiskConfirm = true
                } else {
                    guard let sig = d.sig else { return }
                    doDecide(id: d.id, sig: sig, decision: "approved")
                }
            } label: {
                Label("Approve", systemImage: "checkmark")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(deciding ? Theme.surfaceHigh : Theme.approve)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(deciding)

            // Decline
            Button {
                showDeclineSheet = true
            } label: {
                Label("Decline", systemImage: "xmark")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(deciding ? Theme.surfaceHigh : Theme.decline)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(deciding)
        }
    }

    // MARK: - Actions

    private func load() async {
        guard let client = ConnectionStore.shared.client else {
            error = RelayError.notConfigured.errorDescription; loading = false; return
        }
        do {
            detail = try await client.approvalDetail(id: approvalId)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func doDecide(id: String, sig: String, decision: String, reason: String? = nil, confirmed: Bool = false) {
        deciding = true
        Task {
            do {
                try await model.decide(approvalId: id, sig: sig, decision: decision, reason: reason, confirmed: confirmed)
                decided = true
                try? await Task.sleep(nanoseconds: 800_000_000)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            deciding = false
        }
    }
}

// MARK: - Decline reason sheet

struct DeclineReasonSheet: View {
    var onDone: (String) -> Void
    @State private var reason = ""

    var body: some View {
        VStack(spacing: 10) {
            Text("Reason (optional)")
                .font(.caption.bold())
                .foregroundColor(Theme.textSecond)
            TextField("Dictate or type…", text: $reason)
            HStack {
                Button("Skip") { onDone("") }
                    .foregroundColor(Theme.textMuted)
                Spacer()
                Button("Send") { onDone(reason) }
                    .foregroundColor(Theme.decline)
            }
            .buttonStyle(.plain)
            .font(.body.bold())
        }
        .padding()
        .background(Theme.surface)
    }
}
