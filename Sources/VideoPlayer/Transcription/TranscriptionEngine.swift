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

protocol TranscriptionEngine: Sendable {
    func supportedLocales() async -> [Locale]
    func transcribe(audioAt url: URL, locale: Locale, trackID: UUID) async throws -> [SubtitleCue]
}
