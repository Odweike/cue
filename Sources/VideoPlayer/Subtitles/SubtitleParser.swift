import Foundation

enum SubtitleParserError: LocalizedError {
    case unsupportedFormat
    case noCues
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "Unsupported subtitle format. Use SRT, VTT, or ASS."
        case .noCues: "No readable subtitle cues were found."
        case .unreadableFile: "Couldn't read the subtitle file. Make sure it's a text file."
        }
    }
}

enum SubtitleTextDecoder {
    /// Reads a subtitle file as text. Subtitle files arrive in many legacy
    /// encodings, so UTF-8 is tried first, then common 8-bit code pages.
    /// Windows-1251 is preferred over 1252 when the result contains Cyrillic.
    static func string(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    static func decode(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let cyrillic = String(data: data, encoding: .windowsCP1251),
           cyrillic.contains(where: { $0.isCyrillic }) {
            return cyrillic
        }
        if let western = String(data: data, encoding: .windowsCP1252) {
            return western
        }
        return String(data: data, encoding: .windowsCP1251)
    }
}

private extension Character {
    var isCyrillic: Bool {
        unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
    }
}

enum SubtitleParser {
    static func parse(_ contents: String, fileExtension: String, trackID: UUID) throws -> [SubtitleCue] {
        let cues = switch fileExtension.lowercased() {
        case "srt", "vtt": parseTimedText(contents, trackID: trackID)
        case "ass", "ssa": parseASS(contents, trackID: trackID)
        default: throw SubtitleParserError.unsupportedFormat
        }

        guard !cues.isEmpty else { throw SubtitleParserError.noCues }
        return cues.sorted { $0.startTime < $1.startTime }
    }

    private static func parseTimedText(_ contents: String, trackID: UUID) -> [SubtitleCue] {
        let lines = normalizedLines(contents) + [""]
        var block: [String] = []
        var cues: [SubtitleCue] = []

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if let cue = timedTextCue(from: block, trackID: trackID) {
                    cues.append(cue)
                }
                block.removeAll(keepingCapacity: true)
            } else {
                block.append(line)
            }
        }

        return cues
    }

    private static func timedTextCue(from lines: [String], trackID: UUID) -> SubtitleCue? {
        guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
        let parts = lines[timingIndex].components(separatedBy: "-->")
        guard parts.count == 2,
              let start = timestamp(parts[0]),
              let end = timestamp(parts[1]) else { return nil }

        let text = lines.dropFirst(timingIndex + 1).joined(separator: "\n")
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, end > start else { return nil }
        return SubtitleCue(startTime: start, endTime: end, text: text, trackID: trackID)
    }

    private static func parseASS(_ contents: String, trackID: UUID) -> [SubtitleCue] {
        var fields = ["layer", "start", "end", "style", "name", "marginl", "marginr", "marginv", "effect", "text"]
        var isInEvents = false
        var cues: [SubtitleCue] = []

        for line in normalizedLines(contents) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[Events]" {
                isInEvents = true
                continue
            }
            if trimmed.hasPrefix("[") {
                isInEvents = false
            }
            guard isInEvents else { continue }

            if trimmed.lowercased().hasPrefix("format:") {
                fields = trimmed.dropFirst("format:".count)
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                continue
            }

            guard trimmed.lowercased().hasPrefix("dialogue:") else { continue }
            let payload = trimmed.dropFirst("dialogue:".count)
            let values = payload.split(separator: ",", maxSplits: max(fields.count - 1, 0), omittingEmptySubsequences: false)
                .map(String.init)
            guard let startIndex = fields.firstIndex(of: "start"),
                  let endIndex = fields.firstIndex(of: "end"),
                  let textIndex = fields.firstIndex(of: "text"),
                  values.indices.contains(startIndex),
                  values.indices.contains(endIndex),
                  values.indices.contains(textIndex),
                  let start = timestamp(values[startIndex]),
                  let end = timestamp(values[endIndex]) else { continue }

            let text = values[textIndex]
                .replacingOccurrences(of: "\\N", with: "\n")
                .replacingOccurrences(of: #"\{\\[^}]*\}"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, end > start else { continue }
            cues.append(SubtitleCue(startTime: start, endTime: end, text: text, trackID: trackID))
        }

        return cues
    }

    private static func timestamp(_ rawValue: String) -> TimeInterval? {
        let value = rawValue
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ", maxSplits: 1)
            .first?
            .replacingOccurrences(of: ",", with: ".") ?? ""
        let components = value.split(separator: ":").compactMap { Double($0) }
        // WebVTT allows both "hh:mm:ss.ttt" and the short "mm:ss.ttt" form.
        switch components.count {
        case 3:
            return components[0] * 3_600 + components[1] * 60 + components[2]
        case 2:
            return components[0] * 60 + components[1]
        default:
            return nil
        }
    }

    private static func normalizedLines(_ contents: String) -> [String] {
        contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }
}
