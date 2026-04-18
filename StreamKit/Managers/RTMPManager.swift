import AVFoundation
import Foundation
import HaishinKit
import RTMPHaishinKit

@MainActor
final class RTMPManager: ObservableObject {
    struct OutputState: Identifiable, Equatable {
        let id: StreamPlatform
        let platform: StreamPlatform
        let isConnected: Bool
        let bitrateKbps: Int
        let detail: String
    }

    @Published private(set) var isStreaming = false
    @Published private(set) var outputStates: [OutputState] = []
    @Published private(set) var lastError: String?

    private let config: StreamingConfig
    private var publishers: [StreamPlatform: PlatformPublisher] = [:]
    private var statusTasks: [StreamPlatform: Task<Void, Never>] = [:]
    private var bitrateTasks: [StreamPlatform: Task<Void, Never>] = [:]
    private weak var cameraManager: CameraManager?

    init(config: StreamingConfig = .default) {
        self.config = config
    }

    func prepareForStreaming(with cameraManager: CameraManager) async throws {
        if !cameraManager.isConfigured {
            try await cameraManager.configureIfNeeded()
        }
        self.cameraManager = cameraManager

        AppLogger.stream.info("Prepared stream session (bitrate: \(self.config.videoBitrate))")
    }

    func startSimulcast(destinations: [StreamDestination]) async {
        await publish(destinations: destinations)
    }

    func stopSimulcast() async {
        await stop()
    }

    func publish(destinations: [StreamDestination]) async {
        let enabledDestinations = destinations.filter { $0.isEnabled && !$0.streamKey.isEmpty }
        guard !enabledDestinations.isEmpty else {
            lastError = "Enable at least one platform with a stream key."
            outputStates = []
            isStreaming = false
            return
        }
        guard let cameraManager else {
            lastError = "Camera manager is not prepared."
            isStreaming = false
            return
        }

        await stop()
        lastError = nil
        outputStates = enabledDestinations.map { destination in
            OutputState(
                id: destination.platform,
                platform: destination.platform,
                isConnected: false,
                bitrateKbps: 0,
                detail: "Connecting..."
            )
        }

        for destination in enabledDestinations {
            let publisher = PlatformPublisher(destination: destination)
            publishers[destination.platform] = publisher
            cameraManager.addSampleBufferConsumer(publisher)

            await startStatusListener(for: publisher, platform: destination.platform)
            await startBitrateListener(for: publisher, platform: destination.platform)

            do {
                try await publisher.configure(config: config)
                try await publisher.connectAndPublish()
                setOutputState(
                    for: destination.platform,
                    isConnected: true,
                    detail: "Publishing to \(destination.platform.displayName)",
                    bitrateKbps: 0
                )
            } catch {
                setOutputState(
                    for: destination.platform,
                    isConnected: false,
                    detail: "Failed: \(error.localizedDescription)",
                    bitrateKbps: 0
                )
            }
        }

        isStreaming = outputStates.contains(where: { $0.isConnected })
        if !isStreaming {
            lastError = "No active platform connections."
        }
    }

    func stop() async {
        guard isStreaming || !outputStates.isEmpty else { return }

        for task in statusTasks.values {
            task.cancel()
        }
        for task in bitrateTasks.values {
            task.cancel()
        }
        statusTasks.removeAll()
        bitrateTasks.removeAll()

        if let cameraManager {
            for publisher in publishers.values {
                cameraManager.removeSampleBufferConsumer(publisher)
            }
        }

        for publisher in publishers.values {
            await publisher.stop()
        }
        publishers.removeAll()

        outputStates = outputStates.map { output in
            OutputState(
                id: output.platform,
                platform: output.platform,
                isConnected: false,
                bitrateKbps: 0,
                detail: "Stopped"
            )
        }
        isStreaming = false
    }

    private func setOutputState(
        for platform: StreamPlatform,
        isConnected: Bool,
        detail: String,
        bitrateKbps: Int
    ) {
        if let index = outputStates.firstIndex(where: { $0.platform == platform }) {
            outputStates[index] = OutputState(
                id: platform,
                platform: platform,
                isConnected: isConnected,
                bitrateKbps: bitrateKbps,
                detail: detail
            )
        }
    }

    private func startStatusListener(for publisher: PlatformPublisher, platform: StreamPlatform) async {
        statusTasks[platform]?.cancel()
        statusTasks[platform] = Task { [weak self] in
            guard let self else { return }
            for await status in await publisher.statusStream {
                await MainActor.run {
                    if status.code == RTMPConnection.Code.connectSuccess.rawValue {
                        self.setOutputState(
                            for: platform,
                            isConnected: true,
                            detail: "Connected",
                            bitrateKbps: 0
                        )
                    } else if status.code == RTMPConnection.Code.connectClosed.rawValue {
                        self.setOutputState(
                            for: platform,
                            isConnected: false,
                            detail: "Disconnected",
                            bitrateKbps: 0
                        )
                    } else if status.level == "error" {
                        self.setOutputState(
                            for: platform,
                            isConnected: false,
                            detail: status.description,
                            bitrateKbps: 0
                        )
                        self.lastError = status.description
                    }
                }
            }
        }
    }

    private func startBitrateListener(for publisher: PlatformPublisher, platform: StreamPlatform) async {
        bitrateTasks[platform]?.cancel()
        bitrateTasks[platform] = Task { [weak self] in
            guard let self else { return }
            for await kbps in await publisher.bitrateStream {
                await MainActor.run {
                    if let index = self.outputStates.firstIndex(where: { $0.platform == platform }) {
                        let state = self.outputStates[index]
                        self.outputStates[index] = OutputState(
                            id: platform,
                            platform: platform,
                            isConnected: state.isConnected,
                            bitrateKbps: kbps,
                            detail: state.detail
                        )
                    }
                }
            }
        }
    }
}

actor PlatformPublisher: CameraSampleBufferConsumer {
    let destination: StreamDestination
    let connection: RTMPConnection
    let stream: RTMPStream

    private(set) var currentBitrateKbps: Int = 0
    private var isPublishing = false
    private var continuation: AsyncStream<Int>.Continuation?

    var statusStream: AsyncStream<RTMPStatus> {
        get async {
            await connection.status
        }
    }

    var bitrateStream: AsyncStream<Int> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    init(destination: StreamDestination) {
        self.destination = destination
        self.connection = RTMPConnection()
        self.stream = RTMPStream(connection: connection, fcPublishName: destination.streamKey)

        stream.setBitRateStrategy(PlatformBitRateStrategy { [weak self] kbps in
            Task {
                await self?.updateBitrate(kbps)
            }
        })
    }

    func configure(config: StreamingConfig) async throws {
        var audioSettings = await stream.audioSettings
        audioSettings.bitRate = config.audioBitrate
        try await stream.setAudioSettings(audioSettings)

        var videoSettings = await stream.videoSettings
        videoSettings.bitRate = config.videoBitrate
        videoSettings.expectedFrameRate = Float64(config.frameRate)
        videoSettings.videoSize = config.resolution
        try await stream.setVideoSettings(videoSettings)
    }

    func connectAndPublish() async throws {
        _ = try await connection.connect(destination.platform.rtmpIngestBaseURL.absoluteString)
        _ = try await stream.publish(destination.streamKey, type: .live)
        isPublishing = true
    }

    func stop() async {
        guard isPublishing else { return }
        do {
            _ = try await stream.close()
        } catch {
            AppLogger.stream.error("Stream close failed: \(error.localizedDescription)")
        }
        do {
            try await connection.close()
        } catch {
            AppLogger.stream.error("Connection close failed: \(error.localizedDescription)")
        }
        isPublishing = false
    }

    nonisolated func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
        Task {
            await stream.append(sampleBuffer)
        }
    }

    private func updateBitrate(_ kbps: Int) {
        currentBitrateKbps = kbps
        continuation?.yield(kbps)
    }
}

struct PlatformBitRateStrategy: StreamBitRateStrategy {
    let mamimumVideoBitRate: Int = 0
    let mamimumAudioBitRate: Int = 0

    private let onBitrate: @Sendable (Int) -> Void

    init(onBitrate: @Sendable @escaping (Int) -> Void) {
        self.onBitrate = onBitrate
    }

    func adjustBitrate(_ event: NetworkMonitorEvent, stream: some StreamConvertible) async {
        switch event {
        case .status(let report), .publishInsufficientBWOccured(let report):
            onBitrate(max(0, report.currentBytesOutPerSecond / 1024))
        case .reset:
            onBitrate(0)
        }
    }
}
