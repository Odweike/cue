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

    static func exportSRT(_ track: SubtitleTrack) throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Subtitles"
        panel.prompt = "Export"
        panel.nameFieldStringValue = URL(fileURLWithPath: track.name)
            .deletingPathExtension()
            .lastPathComponent + ".srt"
        panel.allowedContentTypes = [UTType(filenameExtension: "srt")].compactMap { $0 }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try SubtitleFileWriter.writeSRT(track.cues, to: url)
        return url
    }
}
