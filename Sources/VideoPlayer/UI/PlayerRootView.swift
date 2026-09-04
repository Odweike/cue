import SwiftUI

struct PlayerRootView: View {
    let viewModel: PlayerViewModel

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            AVPlayerContainerView(playerView: viewModel.playbackEngine.renderView)

            if viewModel.currentURL == nil {
                WelcomeView {
                    if let url = VideoFilePicker.chooseVideo() {
                        viewModel.open(url)
                    }
                }
            } else {
                FloatingControlsOverlay(viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.currentURL)
        .navigationTitle(viewModel.currentURL?.lastPathComponent ?? "VoxFrame")
    }
}

private struct WelcomeView: View {
    let openVideo: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 58))
                .foregroundStyle(.white.opacity(0.9))

            Text("Open a video to start watching")
                .font(.title2.weight(.medium))
                .foregroundStyle(.white)

            Button("Open Video…", action: openVideo)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("o")
        }
        .padding(40)
        .accessibilityElement(children: .contain)
    }
}
