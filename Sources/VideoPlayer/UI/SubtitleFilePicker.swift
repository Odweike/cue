import AppKit
import UniformTypeIdentifiers

@MainActor
enum SubtitleFilePicker {
    static func chooseSubtitle() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Subtitles"
        panel.prompt = "Open"
        panel.allowedContentTypes = ["srt", "vtt", "ass", "ssa"].compactMap {
            UTType(filenameExtension: $0)
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
