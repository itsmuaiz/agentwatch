import Foundation
#if os(watchOS)
import WatchKit
#elseif os(iOS)
import UIKit
#endif

public enum Haptics {
    /// Used when an approval arrives
    public static func approvalArrived() {
#if os(watchOS)
        WKInterfaceDevice.current().play(.notification)
#elseif os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
#endif
    }

    /// Used on Approve tap
    public static func approved() {
#if os(watchOS)
        WKInterfaceDevice.current().play(.success)
#elseif os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
    }

    /// Used on Decline tap
    public static func declined() {
#if os(watchOS)
        WKInterfaceDevice.current().play(.failure)
#elseif os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
#endif
    }

    /// Light tap for UI selection
    public static func selection() {
#if os(watchOS)
        WKInterfaceDevice.current().play(.click)
#elseif os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
#endif
    }
}
