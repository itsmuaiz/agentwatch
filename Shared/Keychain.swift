import Foundation
import Security

/// Simple Keychain wrapper. All items are stored under kSecAttrService = "com.agentwatch.app".
/// On watchOS we use UserDefaults protected by WKAccessibilityReduceMotion-independent
/// passcode gate (best available on free watchOS) instead of Keychain.
public enum KeychainKey: String {
    case relayURL   = "relay_url"
    case deviceToken = "device_token"
}

public struct Keychain {
    private static let service = "com.agentwatch.app"

    public static func set(_ value: String, for key: KeychainKey) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
        let attrs: [CFString: Any] = query.merging([
            kSecValueData:        data,
            kSecAttrAccessible:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]) { $1 }
        SecItemAdd(attrs as CFDictionary, nil)
    }

    public static func get(_ key: KeychainKey) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      key.rawValue,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(_ key: KeychainKey) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
