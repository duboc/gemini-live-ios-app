import SwiftUI

struct AudioControlBar: View {
    let connectionState: ConnectionState
    let isMicEnabled: Bool
    let onConnectToggle: () -> Void
    let onMicToggle: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            // Connect / Disconnect button
            Button(action: onConnectToggle) {
                Label(
                    connectionState.isConnected ? "Disconnect" : "Connect",
                    systemImage: connectionState.isConnected ? "phone.down.fill" : "phone.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(connectionState.isConnected ? .red : .green)
            .disabled(isConnecting)

            // Mic toggle button
            Button(action: onMicToggle) {
                Image(systemName: isMicEnabled ? "mic.fill" : "mic.slash.fill")
                    .font(.title2)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.bordered)
            .tint(isMicEnabled ? .blue : .gray)
            .disabled(!connectionState.isConnected)
        }
        .padding()
        .background(.bar)
    }

    private var isConnecting: Bool {
        if case .connecting = connectionState { return true }
        return false
    }
}
