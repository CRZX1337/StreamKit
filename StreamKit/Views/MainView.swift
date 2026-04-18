import SwiftUI

@MainActor
struct MainView: View {
    @State private var viewModel = MainViewModel()

    var body: some View {
        ZStack {
            CameraPreviewView(session: viewModel.cameraManager.session)
                .ignoresSafeArea()

            WebOverlayView(webView: viewModel.overlayManager.webView)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                Spacer()
                GlassControlPanel(viewModel: viewModel)
                    .padding()
            }
        }
        .task {
            await viewModel.startPreview()
        }
    }
}

#Preview {
    MainView()
}