import AVFoundation
import Foundation

protocol CameraSampleBufferConsumer: AnyObject {
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer)
}

@MainActor
final class CameraManager: NSObject, ObservableObject {
    enum CameraError: LocalizedError {
        case permissionsDenied
        case inputCreationFailed
        case noVideoDevice

        var errorDescription: String? {
            switch self {
            case .permissionsDenied:
                return "Camera or microphone permission was denied."
            case .inputCreationFailed:
                return "Unable to create camera input."
            case .noVideoDevice:
                return "No compatible video camera found."
            }
        }
    }

    @Published private(set) var isConfigured = false
    @Published private(set) var isRunning = false
    @Published private(set) var isUsingFrontCamera = true
    @Published private(set) var isTorchEnabled = false

    let session = AVCaptureSession()

    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private let videoOutputQueue = DispatchQueue(label: "com.example.streamkit.camera.video")
    private let audioOutputQueue = DispatchQueue(label: "com.example.streamkit.camera.audio")
    private let relayQueue = DispatchQueue(label: "com.example.streamkit.camera.relay")
    nonisolated(unsafe) private var consumers: [ObjectIdentifier: WeakConsumerBox] = [:]

    func requestPermissionsIfNeeded() async -> Bool {
        let videoGranted = await AVCaptureDevice.requestAccess(for: .video)
        let audioGranted = await AVCaptureDevice.requestAccess(for: .audio)
        return videoGranted && audioGranted
    }

    func configureIfNeeded() async throws {
        guard !isConfigured else { return }
        guard await requestPermissionsIfNeeded() else {
            throw CameraError.permissionsDenied
        }

        session.beginConfiguration()
        session.sessionPreset = .high

        do {
            let videoDevice = try makeVideoDevice(front: true)
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
                self.videoInput = videoInput
                isUsingFrontCamera = videoDevice.position == .front
            }
        } catch {
            session.commitConfiguration()
            throw CameraError.inputCreationFailed
        }

        if let mic = AVCaptureDevice.default(for: .audio) {
            do {
                let audioInput = try AVCaptureDeviceInput(device: mic)
                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                    self.audioInput = audioInput
                }
            } catch {
                AppLogger.camera.error("Audio input setup failed: \(error.localizedDescription)")
            }
        }

        configureDataOutputsIfNeeded()

        session.commitConfiguration()
        isConfigured = true
    }

    func startSession() {
        guard isConfigured, !session.isRunning else { return }
        session.startRunning()
        isRunning = true
    }

    func stopSession() {
        guard session.isRunning else { return }
        session.stopRunning()
        isRunning = false
    }

    func toggleCameraPosition() throws {
        guard let currentInput = videoInput else { throw CameraError.noVideoDevice }

        let useFront = currentInput.device.position != .front
        let newDevice = try makeVideoDevice(front: useFront)
        let newInput = try AVCaptureDeviceInput(device: newDevice)

        session.beginConfiguration()
        session.removeInput(currentInput)
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            videoInput = newInput
            isUsingFrontCamera = newDevice.position == .front
        } else {
            session.addInput(currentInput)
            session.commitConfiguration()
            throw CameraError.inputCreationFailed
        }
        session.commitConfiguration()
    }

    func toggleTorch() {
        guard let device = videoInput?.device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if device.torchMode == .on {
                device.torchMode = .off
                isTorchEnabled = false
            } else {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                isTorchEnabled = true
            }
            device.unlockForConfiguration()
        } catch {
            AppLogger.camera.error("Torch toggle failed: \(error.localizedDescription)")
        }
    }

    private func makeVideoDevice(front: Bool) throws -> AVCaptureDevice {
        let desiredPosition: AVCaptureDevice.Position = front ? .front : .back
        if let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: desiredPosition
        ) {
            return device
        }
        throw CameraError.noVideoDevice
    }

    func addSampleBufferConsumer(_ consumer: CameraSampleBufferConsumer) {
        consumers[ObjectIdentifier(consumer)] = WeakConsumerBox(consumer)
    }

    func removeSampleBufferConsumer(_ consumer: CameraSampleBufferConsumer) {
        consumers.removeValue(forKey: ObjectIdentifier(consumer))
    }

    private func configureDataOutputsIfNeeded() {
        if session.outputs.contains(videoDataOutput) == false {
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
            if session.canAddOutput(videoDataOutput) {
                session.addOutput(videoDataOutput)
                videoDataOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
            }
        }

        if session.outputs.contains(audioDataOutput) == false {
            if session.canAddOutput(audioDataOutput) {
                session.addOutput(audioDataOutput)
                audioDataOutput.setSampleBufferDelegate(self, queue: audioOutputQueue)
            }
        }
    }

    nonisolated private func relaySampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        relayQueue.async { [weak self] in
            guard let self else { return }
            self.consumers = self.consumers.filter { $0.value.consumer != nil }
            for entry in self.consumers.values {
                entry.consumer?.cameraManager(self, didOutput: sampleBuffer)
            }
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        relaySampleBuffer(sampleBuffer)
    }
}

private final class WeakConsumerBox {
    weak var consumer: CameraSampleBufferConsumer?

    init(_ consumer: CameraSampleBufferConsumer) {
        self.consumer = consumer
    }
}
