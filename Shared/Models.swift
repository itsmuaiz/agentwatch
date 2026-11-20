import Foundation

// MARK: - Enums

public enum Provider: String, Codable, CaseIterable {
    case anthropic, openai, mock
    public var displayName: String {
        switch self { case .anthropic: return "Claude"; case .openai: return "ChatGPT"; case .mock: return "Demo" }
    }
    public var accentHex: String {
        switch self { case .anthropic: return "#D97706"; case .openai: return "#10A37F"; case .mock: return "#6366F1" }
    }
}

public enum AgentStatus: String, Codable {
    case idle, working, waiting
}

public enum Risk: String, Codable {
    case low, medium, high
}

public enum ActionType: String, Codable {
    case send_email, run_command, purchase, code_push, file_delete, other
    public var displayName: String {
        switch self {
        case .send_email: return "Send Email"
        case .run_command: return "Run Command"
        case .purchase: return "Purchase"
        case .code_push: return "Code Push"
        case .file_delete: return "Delete Files"
        case .other: return "Action"
        }
    }
}

public enum ApprovalStatus: String, Codable {
    case pending, approved, declined, expired
}

// MARK: - Models

public struct Agent: Codable, Identifiable {
    public var id: String
    public var name: String
    public var provider: Provider
    public var status: AgentStatus
    public var pendingCount: Int
    public var hasApiKey: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, provider, status
        case pendingCount = "pending_count"
        case hasApiKey = "has_api_key"
    }
}

public struct Approval: Codable, Identifiable {
    public var id: String
    public var agentId: String
    public var agentName: String
    public var actionType: ActionType
    public var title: String
    public var risk: Risk
    public var status: ApprovalStatus
    public var createdAt: Date
    public var expiresAt: Date?
    public var decision: String?
    public var reason: String?

    enum CodingKeys: String, CodingKey {
        case id, title, risk, status, decision, reason
        case agentId = "agent_id"
        case agentName = "agent_name"
        case actionType = "action_type"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

public struct ApprovalDetail: Codable, Identifiable {
    public var id: String
    public var agentId: String
    public var agentName: String
    public var actionType: ActionType
    public var title: String
    public var risk: Risk
    public var status: ApprovalStatus
    public var details: [String: String]
    public var reasoning: String
    public var createdAt: Date
    public var expiresAt: Date?
    public var decision: String?
    public var reason: String?
    public var sig: String?

    enum CodingKeys: String, CodingKey {
        case id, title, risk, status, details, reasoning, decision, reason, sig
        case agentId = "agent_id"
        case agentName = "agent_name"
        case actionType = "action_type"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

public struct ChatMessage: Codable, Identifiable {
    public var id: String
    public var role: String   // "user" | "assistant"
    public var content: String
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, role, content
        case createdAt = "created_at"
    }
}

public struct AuditEntry: Codable, Identifiable {
    public var id: String
    public var approvalId: String
    public var agentId: String
    public var actionType: String
    public var decision: String
    public var actor: String
    public var reason: String?
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, decision, actor, reason
        case approvalId = "approval_id"
        case agentId = "agent_id"
        case actionType = "action_type"
        case createdAt = "created_at"
    }
}

// MARK: - Relay response wrappers

public struct AgentListResponse: Codable {
    public var agents: [Agent]
}

public struct ApprovalListResponse: Codable {
    public var approvals: [Approval]
}

public struct AuditListResponse: Codable {
    public var entries: [AuditEntry]
}

public struct SettingsResponse: Codable {
    public var timeoutSeconds: Int
    enum CodingKeys: String, CodingKey { case timeoutSeconds = "timeout_seconds" }
}

// MARK: - SSE events

public struct HelloEvent: Codable {
    public var pendingCount: Int
    public var approvals: [Approval]
    enum CodingKeys: String, CodingKey {
        case pendingCount = "pending_count"
        case approvals
    }
}

public struct AgentStatusEvent: Codable {
    public var agentId: String
    public var status: AgentStatus
    enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case status
    }
}

public enum RelayEvent {
    case hello(HelloEvent)
    case approvalCreated(Approval)
    case approvalResolved(Approval)
    case agentStatus(AgentStatusEvent)
    case unknown
}

// MARK: - JSON decoders

public extension JSONDecoder {
    static var relay: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }
    // Use this for [String:String] dicts where keys must NOT be converted
    static var plain: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
