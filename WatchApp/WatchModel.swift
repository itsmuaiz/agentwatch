import Foundation
import SwiftUI
import WatchKit
import UserNotifications

/// Central model for the watch app. Owns the SSE event loop, background poll,
/// notification delivery, and all mutable state the views observe.
@MainActor
public final class WatchModel: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    public static let shared = WatchModel()

    // MARK: - Published state

    @Published public var agents: [Agent] = []
    @Published public var pendingApprovals: [Approval] = []
    @Published public var approvalHistory: [Approval] = []
    @Published public var isConnected = false
    @Published public var errorBanner: String?

    // MARK: - Private

    private var sseTask: Task<Void, Never>?
    private var pollScheduled = false

    // MARK: - Lifecycle

    public func start() {
        setupNotificationCategories()
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        startSSE()
    }

    public func stop() {
        sseTask?.cancel()
        sseTask = nil
        isConnected = false
    }

    // MARK: - SSE event loop

    public func startSSE() {
        guard let client = ConnectionStore.shared.client else { return }
        sseTask?.cancel()
        sseTask = Task {
            do {
                for try await event in client.events() {
                    guard !Task.isCancelled else { break }
                    handle(event)
                }
            } catch {
                isConnected = false
                // Reconnect after 5 seconds
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if !Task.isCancelled { startSSE() }
            }
        }
    }

    private func handle(_ event: RelayEvent) {
        switch event {
        case .hello(let h):
            isConnected = true
            pendingApprovals = h.approvals.filter { $0.status == .pending }
            updateBadge()
        case .approvalCreated(let a):
            if !pendingApprovals.contains(where: { $0.id == a.id }) {
                pendingApprovals.insert(a, at: 0)
            }
            updateBadge()
            scheduleLocalNotification(for: a)
            Haptics.approvalArrived()
        case .approvalResolved(let a):
            pendingApprovals.removeAll { $0.id == a.id }
            if !approvalHistory.contains(where: { $0.id == a.id }) {
                approvalHistory.insert(a, at: 0)
            }
            updateBadge()
        case .agentStatus(let s):
            if let idx = agents.firstIndex(where: { $0.id == s.agentId }) {
                agents[idx].status = s.status
            }
        case .unknown:
            break
        }
    }

    // MARK: - Background refresh (best-effort poll)

    public func backgroundRefresh() async {
        guard let client = ConnectionStore.shared.client else { return }
        do {
            let fresh = try await client.approvals(status: "pending")
            // Fire local notifications for new arrivals not yet seen
            let knownIDs = Set(pendingApprovals.map(\.id))
            for a in fresh where !knownIDs.contains(a.id) {
                scheduleLocalNotification(for: a)
                Haptics.approvalArrived()
            }
            pendingApprovals = fresh
            updateBadge()
        } catch {}
        scheduleNextPoll()
    }

    private func scheduleNextPoll() {
        guard !pollScheduled else { return }
        pollScheduled = true
        // Schedule next background refresh in ~15 minutes (best-effort, OS may delay)
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date(timeIntervalSinceNow: 15 * 60),
            userInfo: "poll" as NSString
        ) { _ in }
        // Reset flag after scheduling
        Task { @MainActor in self.pollScheduled = false }
    }

    // MARK: - Decide on approval

    public func decide(approvalId: String, sig: String, decision: String, reason: String? = nil, confirmed: Bool = false) async throws {
        guard let client = ConnectionStore.shared.client else { throw RelayError.notConfigured }
        try await client.decide(id: approvalId, sig: sig, decision: decision, reason: reason, confirmed: confirmed)
        pendingApprovals.removeAll { $0.id == approvalId }
        updateBadge()
        if decision == "approved" {
            Haptics.approved()
        } else {
            Haptics.declined()
        }
    }

    // MARK: - Reload agents

    public func reloadAgents() async {
        guard let client = ConnectionStore.shared.client else { return }
        do { agents = try await client.agents() } catch {}
    }

    // MARK: - Badge

    private func updateBadge() {
        let count = pendingApprovals.count
        SharedDefaults.pendingCount = count
        UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
    }

    // MARK: - Local notifications (for background arrivals and ntfy fallback)

    private func scheduleLocalNotification(for approval: Approval) {
        let content = UNMutableNotificationContent()
        content.title = approval.agentName
        content.body  = approval.title
        content.sound = .default
        content.categoryIdentifier = approval.risk == .high ? "APPROVAL_HIGH" : "APPROVAL"
        content.userInfo = ["approval_id": approval.id]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let req = UNNotificationRequest(identifier: approval.id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req) { _ in }
    }

    // MARK: - Notification categories

    private func setupNotificationCategories() {
        let approve = UNNotificationAction(
            identifier: "APPROVE",
            title: "Approve",
            options: [.authenticationRequired]
        )
        let decline = UNNotificationAction(
            identifier: "DECLINE",
            title: "Decline",
            options: [.destructive, .authenticationRequired]
        )
        let standard = UNNotificationCategory(
            identifier: "APPROVAL",
            actions: [approve, decline],
            intentIdentifiers: [],
            options: []
        )
        // High-risk: only Decline from notification; Approve requires opening the app
        let high = UNNotificationCategory(
            identifier: "APPROVAL_HIGH",
            actions: [decline],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([standard, high])
    }

    // MARK: - UNUserNotificationCenterDelegate

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        guard let approvalId = info["approval_id"] as? String else {
            completionHandler(); return
        }

        Task {
            guard let client = ConnectionStore.shared.client else { completionHandler(); return }
            // Fetch the approval to get the sig
            guard let detail = try? await client.approvalDetail(id: approvalId),
                  let sig = detail.sig else {
                completionHandler(); return
            }

            switch response.actionIdentifier {
            case "APPROVE":
                try? await decide(approvalId: approvalId, sig: sig, decision: "approved")
            case "DECLINE":
                try? await decide(approvalId: approvalId, sig: sig, decision: "declined")
            default:
                break
            }
            completionHandler()
        }
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
