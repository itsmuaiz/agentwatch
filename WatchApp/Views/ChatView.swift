import SwiftUI

struct ChatView: View {
    let agent: Agent
    @StateObject private var vm: ChatViewModel
    @State private var showDictation = false

    init(agent: Agent) {
        self.agent = agent
        _vm = StateObject(wrappedValue: ChatViewModel(agent: agent))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(vm.messages) { msg in
                            BubbleView(message: msg)
                                .id(msg.id)
                        }
                        // Streaming in progress
                        if vm.isStreaming, !vm.streamingText.isEmpty {
                            BubbleView(message: ChatMessage(
                                id: "streaming",
                                role: "assistant",
                                content: vm.streamingText,
                                createdAt: Date()
                            ))
                            .id("streaming")
                        }
                        if vm.isStreaming, vm.streamingText.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(0..<3, id: \.self) { i in
                                    Circle()
                                        .fill(Theme.textMuted)
                                        .frame(width: 5, height: 5)
                                        .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2), value: vm.isStreaming)
                                }
                            }
                            .padding(8)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                }
                .onChange(of: vm.messages.count) { _ in
                    if let last = vm.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onChange(of: vm.isStreaming) { _ in
                    if vm.isStreaming { proxy.scrollTo("streaming", anchor: .bottom) }
                }
            }

            Divider().background(Theme.surfaceHigh)

            // Quick replies + mic
            QuickRepliesBar(vm: vm, showDictation: $showDictation)
        }
        .navigationTitle(agent.name)
        .background(Theme.background)
        .sheet(isPresented: $showDictation) {
            DictationSheet { text in
                showDictation = false
                if !text.isEmpty { vm.send(text) }
            }
        }
        .task { await vm.loadHistory() }
        .onDisappear { vm.stop() }
    }
}

// MARK: - Quick replies bar

struct QuickRepliesBar: View {
    @ObservedObject var vm: ChatViewModel
    @Binding var showDictation: Bool

    private let chips = ["Yes", "No", "Continue", "Stop"]

    var body: some View {
        VStack(spacing: 6) {
            // Mic button (primary input)
            Button {
                if vm.isStreaming { vm.stop() } else { showDictation = true }
            } label: {
                Image(systemName: vm.isStreaming ? "stop.circle.fill" : "mic.fill")
                    .font(.title2)
                    .foregroundColor(vm.isStreaming ? Theme.decline : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(vm.isStreaming ? Theme.surfaceHigh : Theme.waiting)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)

            // Quick-reply chips
            HStack(spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    Button(chip) { vm.quickReply(chip) }
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Theme.surfaceHigh)
                        .cornerRadius(8)
                        .foregroundColor(Theme.textPrimary)
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }
}

// MARK: - Dictation sheet

struct DictationSheet: View {
    var onDone: (String) -> Void
    @State private var text = ""

    var body: some View {
        VStack(spacing: 12) {
            TextField("Say something…", text: $text)
            Button("Send") { onDone(text) }
                .disabled(text.isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(Theme.waiting)
        }
        .padding()
        .background(Theme.surface)
    }
}
