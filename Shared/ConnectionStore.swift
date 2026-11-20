import Foundation

/// Holds the relay URL + device token and vends a RelayClient.
/// On iOS the values come from Keychain; on watchOS from UserDefaults
/// (populated by WatchConnectivity from the phone).
@MainActor
public final class ConnectionStore: ObservableObject {
    public static let shared = ConnectionStore()

    @Published public private(set) var client: RelayClient?
    @Published public private(set) var isConfigured = false

    // watchOS stores creds in UserDefaults (no Keychain API on watch)
    // iOS stores them in Keychain
#if os(watchOS)
    private static let urlKey   = "aw_relay_url"
    private static let tokenKey = "aw_device_token"

    private static func loadFromDefaults() -> (url: String, token: String)? {
        let d = UserDefaults.standard
        guard let u = d.string(forKey: urlKey), let t = d.string(forKey: tokenKey) else { return nil }
        return (u, t)
    }

    public static func saveToDefaults(url: String, token: String) {
        UserDefaults.standard.set(url,   forKey: urlKey)
        UserDefaults.standard.set(token, forKey: tokenKey)
    }
#endif

    private init() {
        reload()
    }

    public func reload() {
        var urlStr: String?
        var token:  String?

#if os(watchOS)
        if let pair = Self.loadFromDefaults() {
            urlStr = pair.url
            token  = pair.token
        }
#else
        urlStr = Keychain.get(.relayURL)
        token  = Keychain.get(.deviceToken)
#endif

        guard let us = urlStr, let t = token, let url = URL(string: us) else {
            client = nil
            isConfigured = false
            return
        }
        client = RelayClient(baseURL: url, token: t)
        isConfigured = true
    }

    public func save(relayURL: String, token: String) {
#if os(watchOS)
        Self.saveToDefaults(url: relayURL, token: token)
#else
        Keychain.set(relayURL, for: .relayURL)
        Keychain.set(token,   for: .deviceToken)
#endif
        reload()
    }

    public func clear() {
#if os(watchOS)
        UserDefaults.standard.removeObject(forKey: Self.urlKey)
        UserDefaults.standard.removeObject(forKey: Self.tokenKey)
#else
        Keychain.delete(.relayURL)
        Keychain.delete(.deviceToken)
#endif
        client = nil
        isConfigured = false
    }
}
