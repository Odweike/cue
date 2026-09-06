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
    private let audioExtractor = AudioExtractor()

    func supportedLocales() async -> [Locale] {
        async let speechLocales = SpeechTranscriber.supportedLocales
        async let dictationLocales = DictationTranscriber.supportedLocales
        let locales = await speechLocales + dictationLocales
        return Dictionary(grouping: locales, by: \.identifier)
            .compactMap(\.value.first)
    }

    func transcribe(
        audioAt url: URL,
        locale: Locale,
        trackID: UUID,
        progress: @escaping @Sendable (TranscriptionActivity) -> Void
    ) async throws -> [SubtitleCue] {
        let speechLocales = await SpeechTranscriber.supportedLocales
        let dictationLocales = await DictationTranscriber.supportedLocales
        guard !speechLocales.isEmpty || !dictationLocales.isEmpty else {
            throw SpeechTranscriptionError.unavailable
        }
        if let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return try await transcribeSpeech(
                audioAt: url,
                locale: supportedLocale,
                trackID: trackID,
                progress: progress
            )
        }

        if let supportedLocale = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            return try await transcribeDictation(
                audioAt: url,
                locale: supportedLocale,
                trackID: trackID,
                progress: progress
            )
        }

        throw SpeechTranscriptionError.unsupportedLocale
    }

    func progressiveTranscription(
        audioAt url: URL,
        locale: Locale,
        trackID: UUID,
        startingAt time: TimeInterval,
        progress: @escaping @Sendable (TranscriptionActivity) -> Void
    ) -> AsyncThrowingStream<SubtitleCue, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let speechLocales = await SpeechTranscriber.supportedLocales
                    let dictationLocales = await DictationTranscriber.supportedLocales
                    guard !speechLocales.isEmpty || !dictationLocales.isEmpty else {
                        throw SpeechTranscriptionError.unavailable
                    }

                    if let supportedLocale = await SpeechTranscriber.supportedLocale(
                        equivalentTo: locale
                    ) {
                        try await streamSpeech(
                            audioAt: url,
                            locale: supportedLocale,
                            trackID: trackID,
                            startingAt: time,
                            progress: progress,
                            continuation: continuation
                        )
                    } else if let supportedLocale = await DictationTranscriber.supportedLocale(
                        equivalentTo: locale
                    ) {
                        try await streamDictation(
                            audioAt: url,
                            locale: supportedLocale,
                            trackID: trackID,
                            startingAt: time,
                            progress: progress,
                            continuation: continuation
                        )
                    } else {
                        throw SpeechTranscriptionError.unsupportedLocale
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func transcribeSpeech(
        audioAt url: URL,
        locale: Locale,
        trackID: UUID,
        progress: @escaping @Sendable (TranscriptionActivity) -> Void
    ) async throws -> [SubtitleCue] {
        progress(.extractingAudio)
        let extractedURL = try await audioExtractor.extract(from: url)
        defer { try? FileManager.default.removeItem(at: extractedURL) }
        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .timeIndexedTranscriptionWithAlternatives
        )
        let audioFile = try AVAudioFile(forReading: extractedURL)
        try await installAssetsIfNeeded(for: transcriber, progress: progress)
        progress(.recognizing)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        async let cues = collectSpeechResults(from: transcriber, trackID: trackID)
        try await analyze(audioFile, with: analyzer)
        return try await validated(cues)
    }

    private func transcribeDictation(
        audioAt url: URL,
        locale: Locale,
        trackID: UUID,
        progress: @escaping @Sendable (TranscriptionActivity) -> Void
    ) async throws -> [SubtitleCue] {
        progress(.extractingAudio)
        let extractedURL = try await audioExtractor.extract(from: url)
        defer { try? FileManager.default.removeItem(at: extractedURL) }
        let transcriber = DictationTranscriber(locale: locale, preset: .timeIndexedLongDictation)
        let audioFile = try AVAudioFile(forReading: extractedURL)
        try await installAssetsIfNeeded(for: transcriber, progress: progress)
        progress(.recognizing)
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

    private func installAssetsIfNeeded(
        for module: any SpeechModule,
        progress: @escaping @Sendable (TranscriptionActivity) -> Void
    ) async throws {
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            let progressTask = Task {
                while !Task.isCancelled {
                    progress(.preparingLanguage(installation.progress.fractionCompleted))
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            defer { progressTask.cancel() }
            try await installation.downloadAndInstall()
            progress(.preparingLanguage(1))
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

    private func streamSpeech(
        audioAt url: URL,
        locale: Locale,
        trackID: UUID,
        startingAt time: TimeInterval,
        progress: @escaping @Sendable (TranscriptionActivity) -> Void,
        continuation: AsyncThrowingStream<SubtitleCue, Error>.Continuation
    ) async throws {
        progress(.extractingAudio)
        let extractedURL = try await audioExtractor.extract(from: url, startingAt: time)
        defer { try? FileManager.default.removeItem(at: extractedURL) }
        let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        let audioFile = try AVAudioFile(forReading: extractedURL)
        try await installAssetsIfNeeded(for: transcriber, progress: progress)
        progress(.recognizing)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        async let analysis: Void = analyze(audioFile, with: analyzer)

        for try await result in transcriber.results where result.isFinal {
            try Task.checkCancellation()
            if let cue = cue(text: result.text, range: result.range, trackID: trackID, offset: time) {
                continuation.yield(cue)
            }
        }
        try await analysis
    }

    private func streamDictation(
        audioAt url: URL,
        locale: Locale,
        trackID: UUID,
        startingAt time: TimeInterval,
        progress: @escaping @Sendable (TranscriptionActivity) -> Void,
        continuation: AsyncThrowingStream<SubtitleCue, Error>.Continuation
    ) async throws {
        progress(.extractingAudio)
        let extractedURL = try await audioExtractor.extract(from: url, startingAt: time)
        defer { try? FileManager.default.removeItem(at: extractedURL) }
        let transcriber = DictationTranscriber(locale: locale, preset: .timeIndexedLongDictation)
        let audioFile = try AVAudioFile(forReading: extractedURL)
        try await installAssetsIfNeeded(for: transcriber, progress: progress)
        progress(.recognizing)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        async let analysis: Void = analyze(audioFile, with: analyzer)

        for try await result in transcriber.results where result.isFinal {
            try Task.checkCancellation()
            if let cue = cue(text: result.text, range: result.range, trackID: trackID, offset: time) {
                continuation.yield(cue)
            }
        }
        try await analysis
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
        trackID: UUID,
        offset: TimeInterval = 0
    ) -> SubtitleCue? {
        let text = String(attributedText.characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let start = CMTimeGetSeconds(range.start)
        let duration = CMTimeGetSeconds(range.duration)
        guard !text.isEmpty, start.isFinite, duration.isFinite, duration > 0 else { return nil }
        return SubtitleCue(
            startTime: start + offset,
            endTime: start + offset + duration,
            text: text,
            trackID: trackID
        )
    }
}
