import Foundation

enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var label: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting..."
        case .connected: "Connected"
        case .error(let msg): "Error: \(msg)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}
