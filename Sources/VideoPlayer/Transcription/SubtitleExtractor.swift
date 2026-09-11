import Foundation
import Libmpv

enum SubtitleExtractionError: LocalizedError {
    case unavailable
    case failed(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Couldn’t start the local subtitle extractor."
        case .failed(let message):
            "Couldn’t extract embedded subtitles: \(message)"
        case .empty:
            "The embedded subtitle track was empty."
        }
    }
}

struct SubtitleExtractor: Sendable {
    func extract(from sourceURL: URL, stream: SubtitleStream) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            if let ffmpeg = Self.ffmpegExecutable {
                return try Self.extractWithFFmpeg(
                    ffmpeg,
                    from: sourceURL,
                    stream: stream
                )
            }
            return try Self.extractSynchronously(from: sourceURL, stream: stream)
        }.value
    }

    private static var ffmpegExecutable: String? {
        ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func extractWithFFmpeg(
        _ ffmpeg: String,
        from sourceURL: URL,
        stream: SubtitleStream
    ) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueSubtitles", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(stream.fileExtension)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = [
            "-y", "-v", "error",
            "-i", sourceURL.path(percentEncoded: false),
            "-map", stream.ffmpegMap,
            "-f", stream.fileExtension,
            outputURL.path(percentEncoded: false)
        ]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw SubtitleExtractionError.failed(error.isEmpty ? "ffmpeg failed" : error)
        }
        let contents = try String(contentsOf: outputURL, encoding: .utf8)
        guard !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SubtitleExtractionError.empty
        }
        return contents
    }

    private static func extractSynchronously(from sourceURL: URL, stream: SubtitleStream) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueSubtitles", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(stream.fileExtension)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        guard let context = mpv_create() else { throw SubtitleExtractionError.unavailable }
        var isContextAlive = true
        defer {
            if isContextAlive {
                mpv_terminate_destroy(context)
            }
        }

        try setOption("config", to: "no", on: context)
        try setOption("terminal", to: "no", on: context)
        try setOption("vid", to: "no", on: context)
        try setOption("aid", to: "no", on: context)
        try setOption("sid", to: String(stream.id), on: context)
        try setOption("untimed", to: "yes", on: context)
        try setOption("o", to: outputURL.path(percentEncoded: false), on: context)
        try setOption("of", to: stream.fileExtension, on: context)

        let initializationStatus = mpv_initialize(context)
        guard initializationStatus >= 0 else {
            throw SubtitleExtractionError.failed(MPV.errorMessage(for: initializationStatus))
        }

        try command(["loadfile", sourceURL.path(percentEncoded: false), "replace"], on: context)
        extractionLoop: while true {
            try Task.checkCancellation()
            let event = mpv_wait_event(context, 0.1).pointee
            switch event.event_id {
            case MPV_EVENT_END_FILE:
                if let data = event.data?.assumingMemoryBound(to: mpv_event_end_file.self),
                   data.pointee.error < 0 {
                    throw SubtitleExtractionError.failed(MPV.errorMessage(for: data.pointee.error))
                }
                break extractionLoop
            case MPV_EVENT_SHUTDOWN:
                throw SubtitleExtractionError.failed("the decoder stopped unexpectedly")
            default:
                continue
            }
        }

        mpv_terminate_destroy(context)
        isContextAlive = false

        let contents = try String(contentsOf: outputURL, encoding: .utf8)
        guard !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SubtitleExtractionError.empty
        }
        return contents
    }

    private static func setOption(
        _ name: String,
        to value: String,
        on context: OpaquePointer
    ) throws {
        let status = MPV.setOption(name, to: value, on: context)
        guard status >= 0 else {
            throw SubtitleExtractionError.failed("\(name): \(MPV.errorMessage(for: status))")
        }
    }

    private static func command(_ values: [String], on context: OpaquePointer) throws {
        let status = MPV.command(values, on: context)
        guard status >= 0 else {
            throw SubtitleExtractionError.failed(MPV.errorMessage(for: status))
        }
    }
}
