import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum VideoFilePicker {
    static func canOpen(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        return url.pathExtension.lowercased() == "mkv"
            || UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true
    }

    static func chooseVideo() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Video"
        panel.prompt = "Open"
        panel.allowedContentTypes = [
            .movie,
            .mpeg4Movie,
            .quickTimeMovie,
            UTType(filenameExtension: "mkv")
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

struct OpenVideoCommands: Commands {
    let viewModel: PlayerViewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Video…") {
                if let url = VideoFilePicker.chooseVideo() {
                    viewModel.open(url)
                }
            }
            .keyboardShortcut("o")
        }
    }
}

struct PlaybackCommands: Commands {
    let viewModel: PlayerViewModel

    var body: some Commands {
        CommandMenu("Playback") {
            Button(viewModel.isPlaying ? "Pause" : "Play") {
                viewModel.togglePlayback()
            }
            .disabled(viewModel.currentURL == nil)
        }
    }
}
