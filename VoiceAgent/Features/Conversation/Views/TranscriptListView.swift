import SwiftUI

struct TranscriptListView: View {
    let messages: [TranscriptMessage]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) {
                if let lastMessage = messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: TranscriptMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(roleLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(message.text)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleColor)
                    .foregroundStyle(textColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            if message.role != .user { Spacer(minLength: 60) }
        }
    }

    private var roleLabel: String {
        switch message.role {
        case .user: "You"
        case .agent: "Agent"
        case .system: "System"
        }
    }

    private var bubbleColor: Color {
        switch message.role {
        case .user: .blue
        case .agent: Color(.secondarySystemBackground)
        case .system: Color(.tertiarySystemBackground)
        }
    }

    private var textColor: Color {
        switch message.role {
        case .user: .white
        case .agent, .system: .primary
        }
    }
}
