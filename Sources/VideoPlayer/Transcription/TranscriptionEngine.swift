import Foundation

enum TranscriptionStatus: Equatable {
    case idle
    case running
    case completed(URL)
    case failed(String)

    var isRunning: Bool {
        self == .running
    }
}

enum TranscriptionActivity: Equatable, Sendable {
    case extractingAudio
    case preparingLanguage(Double)
    case recognizing
}

protocol TranscriptionEngine: Sendable {
    func supportedLocales() async -> [Locale]
    func transcribe(
        audioAt url: URL,
        locale: Locale,
        trackID: UUID,
        progress: @escaping @Sendable (TranscriptionActivity) -> Void
    ) async throws -> [SubtitleCue]
    func progressiveTranscription(
        audioAt url: URL,
        locale: Locale,
        trackID: UUID,
        startingAt time: TimeInterval,
        progress: @escaping @Sendable (TranscriptionActivity) -> Void
    ) -> AsyncThrowingStream<SubtitleCue, Error>
}
