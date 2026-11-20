import SwiftUI

/// Per-action-type rule: ask (default) / auto-approve / block.
struct RulesView: View {
    @EnvironmentObject var model: PhoneModel
    @State private var local: [String: String] = [:]
    @State private var saving = false
    @State private var error: String?

    private let modes = ["ask", "auto", "block"]
    private let actionTypes = ActionType.allCases

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Action rules")) {
                    ForEach(actionTypes, id: \.rawValue) { at in
                        Picker(at.displayName, selection: binding(for: at.rawValue)) {
                            ForEach(modes, id: \.self) { m in Text(m.capitalized).tag(m) }
                        }
                    }
                }
                if let e = error {
                    Section { Text(e).foregroundColor(Theme.decline).font(.caption) }
                }
                Section {
                    Button(saving ? "Saving…" : "Save rules") { save() }
                        .disabled(saving)
                }
                Section(header: Text("About")) {
                    Text("ask – you decide every time\nauto – automatically approved\nblock – automatically declined")
                        .font(.caption)
                        .foregroundColor(Theme.textSecond)
                }
            }
            .navigationTitle("Rules")
            .onAppear { local = model.rules }
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { local[key] ?? "ask" },
            set: { local[key] = $0 }
        )
    }

    private func save() {
        saving = true; error = nil
        Task {
            do { try await model.saveRules(local) }
            catch { self.error = error.localizedDescription }
            saving = false
        }
    }
}
