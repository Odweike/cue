import SwiftUI

@main
struct VoxFrameApp: App {
    @State private var viewModel: PlayerViewModel

    init() {
        let engine = AVPlaybackEngine()
        _viewModel = State(initialValue: PlayerViewModel(playbackEngine: engine))
    }

    var body: some Scene {
        WindowGroup("VoxFrame") {
            PlayerRootView(viewModel: viewModel)
                .frame(minWidth: 720, minHeight: 440)
        }
        .defaultSize(width: 1_000, height: 640)
        .commands {
            OpenVideoCommands(viewModel: viewModel)
        }
    }
}
