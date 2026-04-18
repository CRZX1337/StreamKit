import Foundation
import Observation

@MainActor
@Observable
final class MainViewModel {
    let cameraManager: CameraManager
    let overlayManager: OverlayManager
    let rtmpManager: RTMPManager

    var destinations: [StreamDestination]
    var overlayURLText = ""
    var sessionState: StreamSessionState = .idle
    var userMessage: String?

    init(
        cameraManager: CameraManager = CameraManager(),
        overlayManager: OverlayManager = OverlayManager(),
        rtmpManager: RTMPManager = RTMPManager()
    ) {
        self.cameraManager = cameraManager
        self.overlayManager = overlayManager
        self.rtmpManager = rtmpManager
        self.destinations = StreamPlatform.allCases.map { StreamDestination(platform: $0) }
    }

    func startPreview() async {
        do {
            try await cameraManager.configureIfNeeded()
            cameraManager.startSession()
            sessionState = .previewing
            userMessage = nil
        } catch {
            sessionState = .failed(message: error.localizedDescription)
            userMessage = error.localizedDescription
        }
    }

    func stopPreview() {
        cameraManager.stopSession()
        if !rtmpManager.isStreaming {
            sessionState = .idle
        }
    }

    func toggleStream(for platform: StreamPlatform, isEnabled: Bool) {
        guard let index = destinations.firstIndex(where: { $0.platform == platform }) else { return }
        destinations[index].isEnabled = isEnabled
    }

    func updateStreamKey(for platform: StreamPlatform, streamKey: String) {
        guard let index = destinations.firstIndex(where: { $0.platform == platform }) else { return }
        destinations[index].streamKey = streamKey
    }

    func startStreaming() async {
        sessionState = .connecting
        do {
            try await rtmpManager.prepareForStreaming(with: cameraManager)
            await rtmpManager.startSimulcast(destinations: destinations)
            let activeCount = rtmpManager.outputStates.filter(\.isConnected).count
            if activeCount > 0 {
                sessionState = .live(activeOutputs: activeCount)
                userMessage = nil
            } else {
                let message = rtmpManager.lastError ?? "Unable to start streaming."
                sessionState = .failed(message: message)
                userMessage = message
            }
        } catch {
            let message = error.localizedDescription
            sessionState = .failed(message: message)
            userMessage = message
        }
    }

    func stopStreaming() async {
        await rtmpManager.stopSimulcast()
        sessionState = cameraManager.isRunning ? .previewing : .idle
    }

    func switchCamera() {
        do {
            try cameraManager.toggleCameraPosition()
        } catch {
            userMessage = error.localizedDescription
        }
    }

    func toggleTorch() {
        cameraManager.toggleTorch()
    }

    func updateOverlayURL() {
        guard !overlayURLText.isEmpty else { return }
        do {
            try overlayManager.loadOverlay(from: overlayURLText)
        } catch {
            userMessage = error.localizedDescription
        }
    }
}
