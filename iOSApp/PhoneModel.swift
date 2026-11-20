import Foundation
import SwiftUI

@MainActor
final class PhoneModel: ObservableObject {
    @Published var agents: [Agent] = []
    @Published var approvals: [Approval] = []
    @Published var auditEntries: [AuditEntry] = []
    @Published var rules: [String: String] = [:]
    @Published var settings: SettingsResponse?
    @Published var isLoading = false
    @Published var error: String?

    func reload() async {
        guard let client = ConnectionStore.shared.client else { return }
        isLoading = true
        async let a = client.agents()
        async let p = client.approvals(status: "all")
        async let r = client.rules()
        async let s = client.settings()
        async let au = client.audit()
        do {
            (agents, approvals, rules, settings, auditEntries) = try await (a, p, r, s, au)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func decide(approvalId: String, sig: String, decision: String, reason: String? = nil) async throws {
        guard let client = ConnectionStore.shared.client else { throw RelayError.notConfigured }
        try await client.decide(id: approvalId, sig: sig, decision: decision, reason: reason)
        await reload()
    }

    func saveRules(_ r: [String: String]) async throws {
        guard let client = ConnectionStore.shared.client else { throw RelayError.notConfigured }
        try await client.setRules(r)
        rules = r
    }

    func saveTimeout(_ seconds: Int) async throws {
        guard let client = ConnectionStore.shared.client else { throw RelayError.notConfigured }
        try await client.setSettings(timeoutSeconds: seconds)
        settings = SettingsResponse(timeoutSeconds: seconds)
    }
}
