import SwiftUI

@main
struct CueApp: App {
    @State private var viewModel: PlayerViewModel

    init() {
        let engine = AVPlaybackEngine()
        _viewModel = State(initialValue: PlayerViewModel(playbackEngine: engine))
    }

    var body: some Scene {
        WindowGroup("Cue") {
            PlayerRootView(viewModel: viewModel)
                .frame(minWidth: 720, minHeight: 440)
        }
        .defaultSize(width: 1_000, height: 640)
        .commands {
            OpenVideoCommands(viewModel: viewModel)
        }
    }
}
