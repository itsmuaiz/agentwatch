import Foundation

/// Shared UserDefaults between the main app and the widget complication.
/// The App Group is optional: falls back to standard defaults so the widget
/// shows "–" but the rest of the app still works.
public struct SharedDefaults {
    private static let groupID = "group.com.agentwatch.app"
    private static let key     = "pending_count"

    private static var suite: UserDefaults {
        UserDefaults(suiteName: groupID) ?? .standard
    }

    public static var pendingCount: Int {
        get { suite.integer(forKey: key) }
        set { suite.set(newValue, forKey: key) }
    }
}
