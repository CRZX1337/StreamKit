import SwiftUI

@MainActor
struct GlassControlPanel: View {
    @Bindable var viewModel: MainViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("StreamKit")
                .font(.title3.weight(.semibold))

            Text(viewModel.sessionState.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(StreamPlatform.allCases) { platform in
                    platformRow(platform)
                }
            }

            HStack {
                TextField("Overlay URL", text: $viewModel.overlayURLText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Button("Load") {
                    viewModel.updateOverlayURL()
                }
            }

            HStack(spacing: 8) {
                Button("Preview") {
                    Task { await viewModel.startPreview() }
                }

                Button("Go Live") {
                    Task { await viewModel.startStreaming() }
                }
                .tint(.red)

                Button("Stop") {
                    Task { await viewModel.stopStreaming() }
                }
            }
            .buttonStyle(.borderedProminent)

            HStack(spacing: 8) {
                Button("Switch Camera") {
                    viewModel.switchCamera()
                }
                .buttonStyle(.bordered)

                Button(viewModel.cameraManager.isTorchEnabled ? "Torch Off" : "Torch On") {
                    viewModel.toggleTorch()
                }
                .buttonStyle(.bordered)
            }

            if let userMessage = viewModel.userMessage {
                Text(userMessage)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .glassEffect()
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func platformRow(_ platform: StreamPlatform) -> some View {
        let binding = bindingForDestination(platform)
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(
                platform.displayName,
                isOn: Binding(
                    get: { binding.wrappedValue.isEnabled },
                    set: { viewModel.toggleStream(for: platform, isEnabled: $0) }
                )
            )
            TextField(
                "\(platform.displayName) stream key",
                text: Binding(
                    get: { binding.wrappedValue.streamKey },
                    set: { viewModel.updateStreamKey(for: platform, streamKey: $0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
    }

    private func bindingForDestination(_ platform: StreamPlatform) -> Binding<StreamDestination> {
        guard let index = viewModel.destinations.firstIndex(where: { $0.platform == platform }) else {
            return .constant(StreamDestination(platform: platform))
        }
        return $viewModel.destinations[index]
    }
}