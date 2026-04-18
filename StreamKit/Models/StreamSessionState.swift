import Foundation

enum StreamSessionState: Equatable {
    case idle
    case previewing
    case connecting
    case live(activeOutputs: Int)
    case failed(message: String)

    var statusText: String {
        switch self {
        case .idle: return "Idle"
        case .previewing: return "Preview"
        case .connecting: return "Connecting..."
        case .live(let activeOutputs): return "Live (\(activeOutputs))"
        case .failed(let message): return "Error: \(message)"
        }
    }
}
