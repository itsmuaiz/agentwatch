import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct PendingEntry: TimelineEntry {
    let date: Date
    let pendingCount: Int
}

// MARK: - Provider

struct PendingProvider: TimelineProvider {
    func placeholder(in context: Context) -> PendingEntry {
        PendingEntry(date: Date(), pendingCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (PendingEntry) -> Void) {
        completion(PendingEntry(date: Date(), pendingCount: SharedDefaults.pendingCount))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PendingEntry>) -> Void) {
        let entry = PendingEntry(date: Date(), pendingCount: SharedDefaults.pendingCount)
        // Refresh every 5 minutes (best-effort; App Group update is the primary path)
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Views

struct PendingCountView: View {
    let entry: PendingEntry
    @Environment(\.widgetFamily) var family

    var countText: String {
        entry.pendingCount > 0 ? "\(entry.pendingCount)" : "–"
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: "checkmark.shield")
                        .font(.caption2)
                    Text(countText)
                        .font(.body.bold().monospacedDigit())
                }
                .foregroundColor(entry.pendingCount > 0 ? .yellow : .white)
            }
        case .accessoryCorner:
            ZStack {
                AccessoryWidgetBackground()
                Text(countText)
                    .font(.body.bold().monospacedDigit())
                    .widgetLabel("Approvals")
            }
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(entry.pendingCount > 0 ? .yellow : .gray)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Approvals")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(entry.pendingCount > 0 ? "\(entry.pendingCount) pending" : "All clear")
                        .font(.caption.bold())
                }
            }
        default:
            Text(countText)
        }
    }
}

// MARK: - Widget

struct AgentWatchWidget: Widget {
    let kind: String = "AgentWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PendingProvider()) { entry in
            PendingCountView(entry: entry)
                .containerBackground(.black, for: .widget)
                .widgetURL(URL(string: "agentwatch://approvals"))
        }
        .configurationDisplayName("Approvals")
        .description("Shows pending agent approval requests.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular])
    }
}

// MARK: - Bundle entry point

@main
struct AgentWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        AgentWatchWidget()
    }
}
