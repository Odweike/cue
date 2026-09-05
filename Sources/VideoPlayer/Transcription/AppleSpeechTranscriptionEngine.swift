import AVFAudio
import CoreMedia
import Foundation
import Speech

enum SpeechTranscriptionError: LocalizedError {
    case unavailable
    case unsupportedLocale
    case noSpeech

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "On-device speech recognition isn’t available on this Mac."
        case .unsupportedLocale:
            "The selected language isn’t supported by on-device speech recognition."
        case .noSpeech:
            "No recognizable speech was found in this video."
        }
    }
}

struct AppleSpeechTranscriptionEngine: TranscriptionEngine {
    func supportedLocales() async -> [Locale] {
        async let speechLocales = SpeechTranscriber.supportedLocales
        async let dictationLocales = DictationTranscriber.supportedLocales
        let locales = await speechLocales + dictationLocales
        return Dictionary(grouping: locales, by: \.identifier)
            .compactMap(\.value.first)
    }

    func transcribe(audioAt url: URL, locale: Locale, trackID: UUID) async throws -> [SubtitleCue] {
        let speechLocales = await SpeechTranscriber.supportedLocales
        let dictationLocales = await DictationTranscriber.supportedLocales
        guard !speechLocales.isEmpty || !dictationLocales.isEmpty else {
            throw SpeechTranscriptionError.unavailable
        }
        if let supportedLocale = matchingLocale(locale, in: speechLocales) {
            return try await transcribeSpeech(
                audioAt: url,
                locale: supportedLocale,
                trackID: trackID
            )
        }

        if let supportedLocale = matchingLocale(locale, in: dictationLocales) {
            return try await transcribeDictation(
                audioAt: url,
                locale: supportedLocale,
                trackID: trackID
            )
        }

        throw SpeechTranscriptionError.unsupportedLocale
    }

    private func transcribeSpeech(
        audioAt url: URL,
        locale: Locale,
        trackID: UUID
    ) async throws -> [SubtitleCue] {
        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .timeIndexedTranscriptionWithAlternatives
        )
        let audioFile = try AVAudioFile(forReading: url)
        try await installAssetsIfNeeded(for: transcriber)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        async let cues = collectSpeechResults(from: transcriber, trackID: trackID)
        try await analyze(audioFile, with: analyzer)
        return try await validated(cues)
    }

    private func transcribeDictation(
        audioAt url: URL,
        locale: Locale,
        trackID: UUID
    ) async throws -> [SubtitleCue] {
        let transcriber = DictationTranscriber(locale: locale, preset: .timeIndexedLongDictation)
        let audioFile = try AVAudioFile(forReading: url)
        try await installAssetsIfNeeded(for: transcriber)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        async let cues = collectDictationResults(from: transcriber, trackID: trackID)
        try await analyze(audioFile, with: analyzer)
        return try await validated(cues)
    }

    private func validated(_ cues: [SubtitleCue]) throws -> [SubtitleCue] {
        let result = cues.sorted { $0.startTime < $1.startTime }
        guard !result.isEmpty else { throw SpeechTranscriptionError.noSpeech }
        return result
    }

    private func matchingLocale(_ locale: Locale, in supportedLocales: [Locale]) -> Locale? {
        supportedLocales.first { $0.identifier == locale.identifier }
            ?? supportedLocales.first {
                $0.language.languageCode == locale.language.languageCode
                    && $0.region == locale.region
            }
            ?? supportedLocales.first {
                $0.language.languageCode == locale.language.languageCode
            }
    }

    private func installAssetsIfNeeded(for module: any SpeechModule) async throws {
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await installation.downloadAndInstall()
        }
        try Task.checkCancellation()
    }

    private func analyze(_ audioFile: AVAudioFile, with analyzer: SpeechAnalyzer) async throws {
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }
    }

    private func collectSpeechResults(
        from transcriber: SpeechTranscriber,
        trackID: UUID
    ) async throws -> [SubtitleCue] {
        var cues: [SubtitleCue] = []

        for try await result in transcriber.results where result.isFinal {
            try Task.checkCancellation()
            if let cue = cue(text: result.text, range: result.range, trackID: trackID) {
                cues.append(cue)
            }
        }

        return cues
    }

    private func collectDictationResults(
        from transcriber: DictationTranscriber,
        trackID: UUID
    ) async throws -> [SubtitleCue] {
        var cues: [SubtitleCue] = []

        for try await result in transcriber.results where result.isFinal {
            try Task.checkCancellation()
            if let cue = cue(text: result.text, range: result.range, trackID: trackID) {
                cues.append(cue)
            }
        }

        return cues
    }

    private func cue(
        text attributedText: AttributedString,
        range: CMTimeRange,
        trackID: UUID
    ) -> SubtitleCue? {
        let text = String(attributedText.characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let start = CMTimeGetSeconds(range.start)
        let duration = CMTimeGetSeconds(range.duration)
        guard !text.isEmpty, start.isFinite, duration.isFinite, duration > 0 else { return nil }
        return SubtitleCue(
            startTime: start,
            endTime: start + duration,
            text: text,
            trackID: trackID
        )
    }
}
