import SwiftUI

struct PlayerRootView: View {
    let viewModel: PlayerViewModel
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            AVPlayerContainerView(playerView: viewModel.playbackEngine.renderView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if viewModel.currentURL == nil {
                WelcomeView {
                    if let url = VideoFilePicker.chooseVideo() {
                        viewModel.open(url)
                    }
                }
            } else {
                SubtitleOverlay(
                    cues: viewModel.visibleSubtitleCues,
                    styleForTrack: viewModel.subtitleStyle(for:)
                )

                FloatingControlsOverlay(viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.currentURL)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.tint, lineWidth: 3)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: VideoFilePicker.canOpen) else { return false }
            viewModel.open(url)
            return true
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
        .onOpenURL { url in
            if VideoFilePicker.canOpen(url) {
                viewModel.open(url)
            }
        }
        .navigationTitle(viewModel.currentURL?.lastPathComponent ?? "Cue")
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
