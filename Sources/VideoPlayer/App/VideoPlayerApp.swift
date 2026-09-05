import SwiftUI

@main
struct CueApp: App {
    @State private var viewModel: PlayerViewModel

    init() {
        let engine = MPVPlaybackEngine()
        _viewModel = State(initialValue: PlayerViewModel(playbackEngine: engine))
    }

    var body: some Scene {
        Window("Cue", id: "main") {
            PlayerRootView(viewModel: viewModel)
                .frame(
                    minWidth: 720,
                    maxWidth: .infinity,
                    minHeight: 440,
                    maxHeight: .infinity
                )
        }
        .defaultSize(width: 1_000, height: 640)
        .commands {
            OpenVideoCommands(viewModel: viewModel)
            LicensesCommands()
        }

        Window("Open Source Licenses", id: "licenses") {
            LicensesView()
                .frame(minWidth: 560, minHeight: 440)
        }
        .defaultSize(width: 680, height: 640)
    }
}
