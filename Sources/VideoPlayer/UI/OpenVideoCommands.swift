import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum VideoFilePicker {
    static func chooseVideo() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Video"
        panel.prompt = "Open"
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
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

