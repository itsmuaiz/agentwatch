import SwiftUI

struct PhoneChatView: View {
    let agent: Agent
    @StateObject private var vm: ChatViewModel
    @State private var input = ""

    init(agent: Agent) {
        self.agent = agent
        _vm = StateObject(wrappedValue: ChatViewModel(agent: agent))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(vm.messages) { msg in
                            PhoneBubble(message: msg)
                                .id(msg.id)
                        }
                        if vm.isStreaming {
                            PhoneBubble(message: ChatMessage(
                                id: "s", role: "assistant",
                                content: vm.streamingText.isEmpty ? "…" : vm.streamingText,
                                createdAt: Date()
                            ))
                            .id("s")
                        }
                    }
                    .padding()
                }
                .onChange(of: vm.messages.count) { _ in
                    if let l = vm.messages.last { proxy.scrollTo(l.id, anchor: .bottom) }
                }
            }

            Divider()

            HStack(spacing: 10) {
                TextField("Message…", text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)

                Button {
                    let t = input.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    input = ""
                    vm.send(t)
                } label: {
                    Image(systemName: vm.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(vm.isStreaming ? Theme.decline : Theme.waiting)
                }
                .onLongPressGesture { vm.stop() }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle(agent.name)
        .task { await vm.loadHistory() }
    }
}

struct PhoneBubble: View {
    let message: ChatMessage
    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            Text(message.content)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isUser ? Theme.waiting : Theme.surface)
                .foregroundColor(.white)
                .cornerRadius(16)
            if !isUser { Spacer(minLength: 60) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}
