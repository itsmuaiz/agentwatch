import Foundation

/// All network calls to the relay.
/// Stateless struct; callers own the connection details.
public struct RelayClient {
    public let baseURL: URL
    public let token: String          // device token (or admin key for phone)

    private var session: URLSession { .shared }

    // MARK: - Init

    public init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token   = token
    }

    // MARK: - Helpers

    private func url(_ path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    private func req(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var r = URLRequest(url: url(path))
        r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = body
        return r
    }

    private func json<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        let (data, resp) = try await session.data(for: req(path, method: method, body: body))
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "HTTP error"
            throw RelayError.server(msg)
        }
        return try JSONDecoder.relay.decode(T.self, from: data)
    }

    // MARK: - Agents

    public func agents() async throws -> [Agent] {
        let r: AgentListResponse = try await json("/v1/agents")
        return r.agents
    }

    // MARK: - Approvals

    public func approvals(status: String = "pending") async throws -> [Approval] {
        let r: ApprovalListResponse = try await json("/v1/approvals?status=\(status)&limit=50")
        return r.approvals
    }

    public func approvalDetail(id: String) async throws -> ApprovalDetail {
        return try await json("/v1/approvals/\(id)")
    }

    public func decide(id: String, sig: String, decision: String, reason: String? = nil, confirmed: Bool = false) async throws {
        struct Body: Encodable {
            var decision: String
            var sig: String
            var reason: String?
            var confirmed: Bool
        }
        let body = try JSONEncoder().encode(Body(decision: decision, sig: sig, reason: reason, confirmed: confirmed))
        let _: [String: String] = try await json("/v1/approvals/\(id)/decision", method: "POST", body: body)
    }

    // MARK: - Chat (streaming)

    public func chat(agentId: String, text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { cont in
            Task {
                do {
                    struct Body: Encodable { var text: String; var style: String }
                    let bodyData = try JSONEncoder().encode(Body(text: text, style: "concise"))
                    var request = req("/v1/agents/\(agentId)/chat", method: "POST", body: bodyData)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    let (bytes, resp) = try await session.bytes(for: request)
                    guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        cont.finish(throwing: RelayError.server("Chat HTTP error"))
                        return
                    }

                    for try await event in SSEParser(bytes) {
                        switch event.event {
                        case "delta":
                            struct Delta: Decodable { var text: String }
                            if let d = try? JSONDecoder().decode(Delta.self, from: Data(event.data.utf8)) {
                                cont.yield(d.text)
                            }
                        case "error":
                            struct Err: Decodable { var error: String }
                            let msg = (try? JSONDecoder().decode(Err.self, from: Data(event.data.utf8)))?.error ?? "stream error"
                            cont.finish(throwing: RelayError.server(msg))
                            return
                        case "done":
                            cont.finish()
                            return
                        default:
                            break
                        }
                    }
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Live events

    public func events() -> AsyncThrowingStream<RelayEvent, Error> {
        AsyncThrowingStream { cont in
            Task {
                do {
                    var request = req("/v1/events")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 300

                    let (bytes, _) = try await session.bytes(for: request)
                    for try await event in SSEParser(bytes) {
                        cont.yield(parseRelayEvent(event))
                    }
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
        }
    }

    private func parseRelayEvent(_ e: SSEEvent) -> RelayEvent {
        let data = Data(e.data.utf8)
        switch e.event {
        case "hello":
            if let v = try? JSONDecoder.relay.decode(HelloEvent.self, from: data) { return .hello(v) }
        case "approval_created":
            if let v = try? JSONDecoder.relay.decode(Approval.self, from: data) { return .approvalCreated(v) }
        case "approval_resolved":
            if let v = try? JSONDecoder.relay.decode(Approval.self, from: data) { return .approvalResolved(v) }
        case "agent_status":
            if let v = try? JSONDecoder.relay.decode(AgentStatusEvent.self, from: data) { return .agentStatus(v) }
        default: break
        }
        return .unknown
    }

    // MARK: - Messages history

    public func messages(agentId: String) async throws -> [ChatMessage] {
        struct Resp: Decodable { var messages: [ChatMessage] }
        let r: Resp = try await json("/v1/agents/\(agentId)/messages")
        return r.messages
    }

    // MARK: - Rules

    /// Returns raw dict so snake_case keys are preserved.
    public func rules() async throws -> [String: String] {
        struct Resp: Decodable { var rules: [String: String] }
        let (data, _) = try await session.data(for: req("/v1/rules"))
        let r = try JSONDecoder.plain.decode(Resp.self, from: data)
        return r.rules
    }

    public func setRules(_ rules: [String: String]) async throws {
        struct Body: Encodable { var rules: [String: String] }
        let body = try JSONEncoder().encode(Body(rules: rules))
        let _: [String: String] = try await json("/v1/rules", method: "PUT", body: body)
    }

    // MARK: - Settings

    public func settings() async throws -> SettingsResponse {
        return try await json("/v1/settings")
    }

    public func setSettings(timeoutSeconds: Int) async throws {
        struct Body: Encodable { var timeout_seconds: Int }
        let body = try JSONEncoder().encode(Body(timeout_seconds: timeoutSeconds))
        let _: [String: String] = try await json("/v1/settings", method: "PUT", body: body)
    }

    // MARK: - Audit

    public func audit() async throws -> [AuditEntry] {
        let r: AuditListResponse = try await json("/v1/audit")
        return r.entries
    }

    // MARK: - Pairing (static, no token)

    public static func pair(baseURL: URL, adminKey: String) async throws -> String {
        var r = URLRequest(url: baseURL.appendingPathComponent("/v1/pair"))
        r.httpMethod = "POST"
        r.setValue("Bearer \(adminKey)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RelayError.server("Pair failed")
        }
        struct Resp: Decodable { var token: String }
        return try JSONDecoder().decode(Resp.self, from: data).token
    }

    public static func redeemCode(baseURL: URL, code: String) async throws -> String {
        struct Body: Encodable { var code: String }
        var r = URLRequest(url: baseURL.appendingPathComponent("/v1/pair/redeem"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONEncoder().encode(Body(code: code))
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RelayError.server("Invalid or expired code")
        }
        struct Resp: Decodable { var token: String }
        return try JSONDecoder().decode(Resp.self, from: data).token
    }

    // MARK: - Push token registration

    public func registerPushToken(_ pushToken: String) async throws {
        struct Body: Encodable { var push_token: String; var platform: String }
        let body = try JSONEncoder().encode(Body(push_token: pushToken, platform: "apns"))
        let _: [String: String] = try await json("/v1/devices/me/push-token", method: "POST", body: body)
    }

    // MARK: - Stop agent

    public func stopAgent(_ agentId: String) async throws {
        let _: [String: String] = try await json("/v1/agents/\(agentId)/stop", method: "POST")
    }
}

// MARK: - Error

public enum RelayError: LocalizedError {
    case server(String)
    case notConfigured

    public var errorDescription: String? {
        switch self {
        case .server(let m): return m
        case .notConfigured: return "Relay not configured. Open the iPhone app to connect."
        }
    }
}
