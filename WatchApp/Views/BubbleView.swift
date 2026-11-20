import SwiftUI

/// Chat bubble. Long assistant messages show a summary + "Show more" toggle.
struct BubbleView: View {
    let message: ChatMessage
    private let summaryLimit = 120

    @State private var expanded = false

    private var isUser: Bool { message.role == "user" }
    private var isLong: Bool { !isUser && message.content.count > summaryLimit }

    private var displayText: String {
        guard isLong, !expanded else { return message.content }
        return String(message.content.prefix(summaryLimit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
            Text(displayText)
                .font(.caption)
                .foregroundColor(isUser ? .white : Theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isUser ? Theme.waiting : Theme.surface)
                .cornerRadius(12)
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

            if isLong {
                Button(expanded ? "Show less" : "Show more") {
                    expanded.toggle()
                }
                .font(.caption2)
                .foregroundColor(Theme.textSecond)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
            }
        }
    }
}
