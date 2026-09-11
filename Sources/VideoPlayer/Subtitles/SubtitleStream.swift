import Foundation

struct SubtitleStream: Identifiable, Equatable, Sendable {
    let id: Int64
    let ffmpegMap: String
    let title: String?
    let language: String?
    let codec: String?
    let isForced: Bool
    let isDefault: Bool

    var isTextCodec: Bool {
        let codec = codec?.lowercased() ?? ""
        return codec.contains("subrip")
            || codec.contains("srt")
            || codec.contains("ass")
            || codec.contains("ssa")
            || codec.contains("webvtt")
            || codec.contains("vtt")
            || codec.contains("mov_text")
            || codec.contains("text")
    }

    var displayName: String {
        var parts: [String] = []
        if let language, !language.isEmpty {
            parts.append(LanguageName.displayName(for: language))
        }
        if let title, !title.isEmpty {
            parts.append(title)
        }
        if isForced {
            parts.append("Forced")
        }
        if parts.isEmpty {
            parts.append("Subtitle \(id)")
        }
        return parts.joined(separator: " • ")
    }

    var fileExtension: String {
        let codec = codec?.lowercased() ?? ""
        if codec.contains("ass") || codec.contains("ssa") { return "ass" }
        if codec.contains("vtt") { return "vtt" }
        return "srt"
    }
}
