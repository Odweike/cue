import AppKit
import SwiftUI

@MainActor
final class CueAppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = PlayerViewModel(playbackEngine: MPVPlaybackEngine(), watchHistory: .live)
    private let pictureInPicture = PictureInPictureController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        pictureInPicture.attach(viewModel)
        viewModel.pictureInPicture = pictureInPicture
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: VideoFilePicker.canOpen) else { return }
        viewModel.open(url)
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.persistWatchProgress(force: true)
    }

    func applicationDidResignActive(_ notification: Notification) {
        viewModel.persistWatchProgress(force: true)
    }
}

@main
struct CueApp: App {
    @NSApplicationDelegateAdaptor(CueAppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Cue", id: "main") {
            PlayerRootView(viewModel: appDelegate.viewModel)
                .frame(
                    minWidth: 720,
                    maxWidth: .infinity,
                    minHeight: 440,
                    maxHeight: .infinity
                )
        }
        .defaultSize(width: 1_000, height: 640)
        .commands {
            OpenVideoCommands(viewModel: appDelegate.viewModel)
            PlaybackCommands(viewModel: appDelegate.viewModel)
            LicensesCommands()
        }

        Window("Open Source Licenses", id: "licenses") {
            LicensesView()
                .frame(minWidth: 560, minHeight: 440)
        }
        .defaultSize(width: 680, height: 640)
    }
}
