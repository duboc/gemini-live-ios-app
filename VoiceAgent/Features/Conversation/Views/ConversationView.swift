import SwiftUI

struct ConversationView: View {
    @State private var viewModel = ConversationViewModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                connectionStatusBar

                TranscriptListView(messages: viewModel.transcript)

                AudioControlBar(
                    connectionState: viewModel.connectionState,
                    isMicEnabled: viewModel.isMicEnabled,
                    onConnectToggle: {
                        if viewModel.connectionState.isConnected {
                            viewModel.disconnect()
                        } else {
                            viewModel.connect()
                        }
                    },
                    onMicToggle: {
                        viewModel.toggleMicrophone()
                    }
                )
            }
            .navigationTitle("Voice Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(serverURL: $viewModel.serverURL)
            }
        }
    }

    private var connectionStatusBar: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(viewModel.connectionState.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var statusColor: Color {
        switch viewModel.connectionState {
        case .connected: .green
        case .connecting: .orange
        case .disconnected: .gray
        case .error: .red
        }
    }
}

// MARK: - Settings Sheet

private struct SettingsSheet: View {
    @Binding var serverURL: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("WebSocket Server") {
                    TextField("Server URL", text: $serverURL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    ConversationView()
}
