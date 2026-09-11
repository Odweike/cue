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

/// SpeechTranscriber.Result and DictationTranscriber.Result share the same
/// shape but no common protocol — this adapter lets the engine share the
/// collection and streaming logic between the two.
private protocol SpeechResultLike {
    var isFinal: Bool { get }
    var text: AttributedString { get }
    var range: CMTimeRange { get }
}

extension SpeechTranscriber.Result: SpeechResultLike {}
extension DictationTranscriber.Result: SpeechResultLike {}

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
            let transcriber = SpeechTranscriber(
                locale: supportedLocale,
                preset: .timeIndexedTranscriptionWithAlternatives
            )
            return try await transcribeWithModule(
                transcriber,
                cues: cueSequence(from: transcriber.results, trackID: trackID),
                audioAt: url,
                progress: progress
            )
        }

        if let supportedLocale = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            let transcriber = DictationTranscriber(
                locale: supportedLocale,
                preset: .timeIndexedLongDictation
            )
            return try await transcribeWithModule(
                transcriber,
                cues: cueSequence(from: transcriber.results, trackID: trackID),
                audioAt: url,
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
                        let transcriber = SpeechTranscriber(
                            locale: supportedLocale,
                            preset: .timeIndexedProgressiveTranscription
                        )
                        try await streamTranscription(
                            audioAt: url,
                            module: transcriber,
                            cues: cueSequence(from: transcriber.results, trackID: trackID, offset: time),
                            startingAt: time,
                            progress: progress,
                            continuation: continuation
                        )
                    } else if let supportedLocale = await DictationTranscriber.supportedLocale(
                        equivalentTo: locale
                    ) {
                        let transcriber = DictationTranscriber(
                            locale: supportedLocale,
                            preset: .timeIndexedLongDictation
                        )
                        try await streamTranscription(
                            audioAt: url,
                            module: transcriber,
                            cues: cueSequence(from: transcriber.results, trackID: trackID, offset: time),
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

    private func transcribeWithModule<Cues: AsyncSequence>(
        _ module: any SpeechModule,
        cues: sending Cues,
        audioAt url: URL,
        progress: @escaping @Sendable (TranscriptionActivity) -> Void
    ) async throws -> [SubtitleCue] where Cues.Element == SubtitleCue, Cues.Failure == any Error {
        progress(.extractingAudio)
        let extractedURL = try await audioExtractor.extract(from: url)
        defer { try? FileManager.default.removeItem(at: extractedURL) }
        let audioFile = try AVAudioFile(forReading: extractedURL)
        try await installAssetsIfNeeded(for: module, progress: progress)
        progress(.recognizing)
        let analyzer = SpeechAnalyzer(modules: [module])
        async let collected = collectCues(from: cues)
        try await analyze(audioFile, with: analyzer)
        return try await validated(collected)
    }

    private func streamTranscription<Cues: AsyncSequence>(
        audioAt url: URL,
        module: any SpeechModule,
        cues: Cues,
        startingAt time: TimeInterval,
        progress: @escaping @Sendable (TranscriptionActivity) -> Void,
        continuation: AsyncThrowingStream<SubtitleCue, Error>.Continuation
    ) async throws where Cues.Element == SubtitleCue, Cues.Failure == any Error {
        progress(.extractingAudio)
        let extractedURL = try await audioExtractor.extract(from: url, startingAt: time)
        defer { try? FileManager.default.removeItem(at: extractedURL) }
        let audioFile = try AVAudioFile(forReading: extractedURL)
        try await installAssetsIfNeeded(for: module, progress: progress)
        progress(.recognizing)
        let analyzer = SpeechAnalyzer(modules: [module])
        async let analysis: Void = analyze(audioFile, with: analyzer)

        for try await cue in cues {
            try Task.checkCancellation()
            continuation.yield(cue)
        }
        try await analysis
    }

    private func collectCues<Cues: AsyncSequence>(
        from cues: Cues
    ) async throws -> [SubtitleCue] where Cues.Element == SubtitleCue, Cues.Failure == any Error {
        var collected: [SubtitleCue] = []
        for try await cue in cues {
            try Task.checkCancellation()
            collected.append(cue)
        }
        return collected
    }

    private func cueSequence<Results: AsyncSequence>(
        from results: Results,
        trackID: UUID,
        offset: TimeInterval = 0
    ) -> AsyncCompactMapSequence<Results, SubtitleCue> where Results.Element: SpeechResultLike {
        results.compactMap { result in
            guard result.isFinal else { return nil }
            return cue(text: result.text, range: result.range, trackID: trackID, offset: offset)
        }
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
