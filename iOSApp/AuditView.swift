import SwiftUI

struct AuditView: View {
    @EnvironmentObject var model: PhoneModel

    var body: some View {
        NavigationStack {
            List(model.auditEntries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        decisionIcon(entry.decision)
                        Text(entry.actionType.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.body)
                        Spacer()
                        Text(entry.createdAt, style: .date)
                            .font(.caption2)
                            .foregroundColor(Theme.textMuted)
                    }
                    Text("By \(entry.actor)")
                        .font(.caption)
                        .foregroundColor(Theme.textSecond)
                    if let r = entry.reason {
                        Text(""\(r)"")
                            .font(.caption2)
                            .foregroundColor(Theme.textMuted)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Audit Log")
            .refreshable { await model.reload() }
            .overlay {
                if model.auditEntries.isEmpty && !model.isLoading {
                    ContentUnavailableView("No entries yet", systemImage: "list.bullet.rectangle")
                }
            }
        }
    }

    @ViewBuilder
    func decisionIcon(_ d: String) -> some View {
        Image(systemName: d == "approved" ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundColor(d == "approved" ? Theme.approve : Theme.decline)
    }
}
