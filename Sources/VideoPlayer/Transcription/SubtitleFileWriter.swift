import Foundation

enum SubtitleFileWriter {
    static func writeSRT(_ cues: [SubtitleCue], beside videoURL: URL, locale: Locale) throws -> URL {
        let directory = videoURL.deletingLastPathComponent()
        let stem = videoURL.deletingPathExtension().lastPathComponent
        let language = locale.language.languageCode?.identifier ?? locale.identifier
        let baseName = "\(stem).\(language).generated"
        var outputURL = directory.appendingPathComponent(baseName).appendingPathExtension("srt")
        var suffix = 2

        while FileManager.default.fileExists(atPath: outputURL.path) {
            outputURL = directory
                .appendingPathComponent("\(baseName)-\(suffix)")
                .appendingPathExtension("srt")
            suffix += 1
        }

        try srtContents(for: cues).write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    static func srtContents(for cues: [SubtitleCue]) -> String {
        cues.enumerated().map { index, cue in
            """
            \(index + 1)
            \(timestamp(cue.startTime)) --> \(timestamp(cue.endTime))
            \(cue.text)
            """
        }
        .joined(separator: "\n\n") + "\n"
    }

    static func writeSRT(_ cues: [SubtitleCue], to url: URL) throws {
        try srtContents(for: cues).write(to: url, atomically: true, encoding: .utf8)
    }

    private static func timestamp(_ time: TimeInterval) -> String {
        let milliseconds = max(Int((time * 1_000).rounded()), 0)
        let hours = milliseconds / 3_600_000
        let minutes = milliseconds % 3_600_000 / 60_000
        let seconds = milliseconds % 60_000 / 1_000
        let remainder = milliseconds % 1_000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, remainder)
    }
}
