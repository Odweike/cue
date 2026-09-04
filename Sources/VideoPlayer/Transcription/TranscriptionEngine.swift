import Foundation

protocol TranscriptionEngine: Sendable {
    func transcribe(audioAt url: URL, locale: Locale) async throws -> [SubtitleCue]
}

