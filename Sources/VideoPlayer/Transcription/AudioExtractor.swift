import AVFAudio
import Foundation
import Libmpv

enum AudioExtractionError: LocalizedError {
    case unavailable
    case failed(String)
    case noAudio

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Couldn’t start the local audio extractor."
        case .failed(let message):
            "Couldn’t extract audio from this video: \(message)"
        case .noAudio:
            "No usable audio track was found in this video."
        }
    }
}

struct AudioExtractor: Sendable {
    func extract(
        from sourceURL: URL,
        startingAt startTime: TimeInterval = 0,
        duration: TimeInterval? = nil
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try Self.extractSynchronously(
                from: sourceURL,
                startingAt: startTime,
                duration: duration
            )
        }.value
    }

    private static func extractSynchronously(
        from sourceURL: URL,
        startingAt startTime: TimeInterval,
        duration: TimeInterval?
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueTranscription", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        var shouldKeepOutput = false
        defer {
            if !shouldKeepOutput {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        guard let context = mpv_create() else { throw AudioExtractionError.unavailable }
        var isContextAlive = true
        defer {
            if isContextAlive {
                mpv_terminate_destroy(context)
            }
        }

        try setOption("config", to: "no", on: context)
        try setOption("terminal", to: "no", on: context)
        try setOption("untimed", to: "yes", on: context)
        try setOption("video", to: "no", on: context)
        try setOption("ao", to: "pcm", on: context)
        try setOption("ao-pcm-file", to: outputURL.path, on: context)
        try setOption("ao-pcm-waveheader", to: "yes", on: context)
        try setOption("audio-channels", to: "mono", on: context)
        try setOption("audio-samplerate", to: "16000", on: context)
        if startTime > 0 {
            try setOption("start", to: String(startTime), on: context)
        }
        if let duration, duration > 0 {
            try setOption("length", to: String(duration), on: context)
        }

        let initializationStatus = mpv_initialize(context)
        guard initializationStatus >= 0 else {
            throw AudioExtractionError.failed(MPV.errorMessage(for: initializationStatus))
        }

        try command(["loadfile", sourceURL.path, "replace"], on: context)
        extractionLoop: while true {
            try Task.checkCancellation()
            let event = mpv_wait_event(context, 0.1).pointee
            switch event.event_id {
            case MPV_EVENT_END_FILE:
                if let data = event.data?.assumingMemoryBound(to: mpv_event_end_file.self),
                   data.pointee.error < 0 {
                    throw AudioExtractionError.failed(MPV.errorMessage(for: data.pointee.error))
                }
                break extractionLoop
            case MPV_EVENT_SHUTDOWN:
                throw AudioExtractionError.failed("the decoder stopped unexpectedly")
            default:
                continue
            }
        }

        mpv_terminate_destroy(context)
        isContextAlive = false

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue > 44 else {
            throw AudioExtractionError.noAudio
        }
        _ = try AVAudioFile(forReading: outputURL)
        shouldKeepOutput = true
        return outputURL
    }

    private static func setOption(
        _ name: String,
        to value: String,
        on context: OpaquePointer
    ) throws {
        let status = MPV.setOption(name, to: value, on: context)
        guard status >= 0 else {
            throw AudioExtractionError.failed("\(name): \(MPV.errorMessage(for: status))")
        }
    }

    private static func command(_ values: [String], on context: OpaquePointer) throws {
        let status = MPV.command(values, on: context)
        guard status >= 0 else {
            throw AudioExtractionError.failed(MPV.errorMessage(for: status))
        }
    }
}
