import Foundation
import Observation

@MainActor
@Observable
final class PlayerViewModel {
    private static let subtitleStylesKey = "SubtitleStyles"
    private static let subtitleStyleProfilesKey = "SubtitleStyleProfiles"
    private static let transcriptionLocaleKey = "TranscriptionLocale"

    let playbackEngine: any PlaybackEngine
    private let transcriptionEngine: any TranscriptionEngine
    private let userDefaults: UserDefaults
    private var transcriptionTask: Task<Void, Never>?
    private var transcriptionID: UUID?
    private var progressiveTranscriptionTask: Task<Void, Never>?
    private var progressiveTranscriptionID: UUID?
    private var progressiveTrackID: UUID?
    private(set) var currentURL: URL?
    private(set) var playbackState = PlaybackState()
    private(set) var subtitleTracks: [SubtitleTrack] = []
    private(set) var audioTracks: [AudioTrack] = []
    private(set) var subtitleStyles: [SubtitleStyle]
    private(set) var subtitleStyleProfiles: [SubtitleStyleProfile]
    private(set) var supportedTranscriptionLocales: [Locale] = []
    private(set) var transcriptionStatus = TranscriptionStatus.idle
    private(set) var transcriptionActivity: TranscriptionActivity?
    private(set) var progressiveTranscriptionActivity: TranscriptionActivity?
    private(set) var isProgressiveTranscriptionEnabled = false
    private(set) var progressiveTranscriptionError: String?
    private(set) var selectedTranscriptionLocaleIdentifier: String

    init(
        playbackEngine: any PlaybackEngine,
        transcriptionEngine: any TranscriptionEngine = AppleSpeechTranscriptionEngine(),
        userDefaults: UserDefaults = .standard
    ) {
        self.playbackEngine = playbackEngine
        self.transcriptionEngine = transcriptionEngine
        self.userDefaults = userDefaults
        subtitleStyles = Self.loadSubtitleStyles(from: userDefaults)
        subtitleStyleProfiles = Self.loadSubtitleStyleProfiles(from: userDefaults)
        selectedTranscriptionLocaleIdentifier = userDefaults.string(
            forKey: Self.transcriptionLocaleKey
        ) ?? Locale.current.identifier
    }

    func open(_ url: URL) {
        cancelTranscription()
        setProgressiveTranscriptionEnabled(false)
        subtitleTracks.removeAll()
        audioTracks.removeAll()
        playbackEngine.open(url)
        currentURL = url
        refreshPlaybackState()
    }

    func refreshPlaybackState() {
        playbackState = playbackEngine.state
    }

    func togglePlayback() {
        if playbackState.isPlaying {
            playbackEngine.pause()
        } else {
            playbackEngine.play()
        }
        refreshPlaybackState()
    }

    func seek(to time: TimeInterval) {
        playbackEngine.seek(to: time)
        refreshPlaybackState()
    }

    func skip(by interval: TimeInterval) {
        playbackEngine.skip(by: interval)
        refreshPlaybackState()
        restartProgressiveTranscriptionIfNeeded()
    }

    func setVolume(_ volume: Float) {
        playbackEngine.setVolume(volume)
        refreshPlaybackState()
    }

    func setMuted(_ isMuted: Bool) {
        playbackEngine.setMuted(isMuted)
        refreshPlaybackState()
    }

    func toggleMuted() {
        setMuted(!playbackState.isMuted)
    }

    func setPlaybackRate(_ rate: Float) {
        playbackEngine.setPlaybackRate(rate)
        refreshPlaybackState()
    }

    func setVideoScalingMode(_ mode: VideoScalingMode) {
        playbackEngine.setVideoScalingMode(mode)
        refreshPlaybackState()
    }

    func setAspectRatio(_ ratio: VideoRatio) {
        playbackEngine.setAspectRatio(ratio)
        refreshPlaybackState()
    }

    func setCropRatio(_ ratio: VideoRatio) {
        playbackEngine.setCropRatio(ratio)
        refreshPlaybackState()
    }

    func setRotation(_ rotation: VideoRotation) {
        playbackEngine.setRotation(rotation)
        refreshPlaybackState()
    }

    func setHardwareDecoding(_ isEnabled: Bool) {
        playbackEngine.setHardwareDecoding(isEnabled)
        refreshPlaybackState()
    }

    func setDeinterlacing(_ isEnabled: Bool) {
        playbackEngine.setDeinterlacing(isEnabled)
        refreshPlaybackState()
    }

    func setVideoEqualizer(_ equalizer: VideoEqualizer) {
        playbackEngine.setVideoEqualizer(equalizer)
        refreshPlaybackState()
    }

    func refreshAudioTracks() {
        audioTracks = playbackEngine.audioTracks()
    }

    func selectAudioTrack(_ id: Int64) {
        playbackEngine.selectAudioTrack(id)
        refreshAudioTracks()
    }

    func setAudioDelay(_ delay: TimeInterval) {
        playbackEngine.setAudioDelay(delay)
        refreshPlaybackState()
    }

    var visibleSubtitleCues: [SubtitleCue] {
        let time = playbackState.currentTime
        return subtitleTracks
            .filter(\.isEnabled)
            .flatMap(\.cues)
            .filter { $0.startTime <= time && time < $0.endTime }
    }

    func importSubtitles(_ url: URL) throws {
        let trackID = UUID()
        let contents = try String(contentsOf: url, encoding: .utf8)
        let cues = try SubtitleParser.parse(contents, fileExtension: url.pathExtension, trackID: trackID)
        let isEnabled = subtitleTracks.filter(\.isEnabled).count < 2
        subtitleTracks.append(
            SubtitleTrack(id: trackID, name: url.lastPathComponent, cues: cues, isEnabled: isEnabled)
        )
    }

    func setSubtitleTrack(_ trackID: UUID, enabled: Bool) {
        guard let index = subtitleTracks.firstIndex(where: { $0.id == trackID }) else { return }
        if enabled, subtitleTracks.filter(\.isEnabled).count >= 2 { return }
        subtitleTracks[index].isEnabled = enabled
    }

    func subtitleStyle(for trackID: UUID) -> SubtitleStyle {
        let enabledTracks = subtitleTracks.filter(\.isEnabled)
        guard let index = enabledTracks.firstIndex(where: { $0.id == trackID }) else {
            return .primary
        }
        return subtitleStyles[min(index, subtitleStyles.count - 1)]
    }

    func setSubtitleStyle(_ style: SubtitleStyle, at index: Int) {
        guard subtitleStyles.indices.contains(index) else { return }
        subtitleStyles[index] = style.normalized()
        saveSubtitleStyles()
    }

    func resetSubtitleStyle(at index: Int) {
        let defaults: [SubtitleStyle] = [.primary, .secondary]
        guard defaults.indices.contains(index) else { return }
        setSubtitleStyle(defaults[index], at: index)
    }

    @discardableResult
    func saveSubtitleStyleProfile(named rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        if let index = subtitleStyleProfiles.firstIndex(where: {
            $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }) {
            subtitleStyleProfiles[index].name = name
            subtitleStyleProfiles[index].styles = subtitleStyles
        } else {
            subtitleStyleProfiles.append(
                SubtitleStyleProfile(id: UUID(), name: name, styles: subtitleStyles)
            )
        }
        saveSubtitleStyleProfiles()
        return true
    }

    func applySubtitleStyleProfile(_ id: UUID) {
        guard let profile = subtitleStyleProfiles.first(where: { $0.id == id }),
              profile.styles.count == 2 else { return }
        subtitleStyles = profile.styles.map { $0.normalized() }
        saveSubtitleStyles()
    }

    func deleteSubtitleStyleProfile(_ id: UUID) {
        subtitleStyleProfiles.removeAll { $0.id == id }
        saveSubtitleStyleProfiles()
    }

    func loadSupportedTranscriptionLocales() async {
        guard supportedTranscriptionLocales.isEmpty else { return }
        let locales = await transcriptionEngine.supportedLocales()
        supportedTranscriptionLocales = locales.sorted {
            localeName($0) < localeName($1)
        }

        let selected = Locale(identifier: selectedTranscriptionLocaleIdentifier)
        if let equivalent = locales.first(where: {
            $0.language.languageCode == selected.language.languageCode
        }) ?? locales.first {
            selectTranscriptionLocale(equivalent.identifier)
        }
    }

    func selectTranscriptionLocale(_ identifier: String) {
        guard supportedTranscriptionLocales.contains(where: { $0.identifier == identifier }) else { return }
        let shouldRestartProgressiveTranscription = isProgressiveTranscriptionEnabled
        if shouldRestartProgressiveTranscription {
            setProgressiveTranscriptionEnabled(false)
        }
        selectedTranscriptionLocaleIdentifier = identifier
        userDefaults.set(identifier, forKey: Self.transcriptionLocaleKey)
        if shouldRestartProgressiveTranscription {
            setProgressiveTranscriptionEnabled(true)
        }
    }

    func startTranscription() {
        guard transcriptionTask == nil, let videoURL = currentURL else { return }
        let locale = Locale(identifier: selectedTranscriptionLocaleIdentifier)
        let trackID = UUID()
        let operationID = UUID()
        transcriptionID = operationID
        transcriptionStatus = .running
        transcriptionActivity = .extractingAudio

        transcriptionTask = Task { [weak self, transcriptionEngine] in
            do {
                let cues = try await transcriptionEngine.transcribe(
                    audioAt: videoURL,
                    locale: locale,
                    trackID: trackID,
                    progress: { [weak self] activity in
                        Task { @MainActor in
                            guard let self, self.transcriptionID == operationID else { return }
                            self.transcriptionActivity = activity
                        }
                    }
                )
                try Task.checkCancellation()
                let outputURL = try SubtitleFileWriter.writeSRT(
                    cues,
                    beside: videoURL,
                    locale: locale
                )
                guard let self, transcriptionID == operationID else { return }
                let isEnabled = subtitleTracks.filter(\.isEnabled).count < 2
                subtitleTracks.append(
                    SubtitleTrack(
                        id: trackID,
                        name: "Generated • \(localeName(locale))",
                        cues: cues,
                        isEnabled: isEnabled
                    )
                )
                finishTranscription(operationID, with: .completed(outputURL))
            } catch is CancellationError {
                self?.finishTranscription(operationID, with: .idle)
            } catch {
                self?.finishTranscription(operationID, with: .failed(error.localizedDescription))
            }
        }
    }

    func cancelTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        transcriptionID = nil
        transcriptionStatus = .idle
        transcriptionActivity = nil
    }

    func setProgressiveTranscriptionEnabled(_ isEnabled: Bool) {
        guard isEnabled else {
            progressiveTranscriptionTask?.cancel()
            progressiveTranscriptionTask = nil
            progressiveTranscriptionID = nil
            if let progressiveTrackID {
                subtitleTracks.removeAll { $0.id == progressiveTrackID }
            }
            progressiveTrackID = nil
            isProgressiveTranscriptionEnabled = false
            progressiveTranscriptionError = nil
            progressiveTranscriptionActivity = nil
            return
        }
        guard currentURL != nil, !supportedTranscriptionLocales.isEmpty else { return }
        isProgressiveTranscriptionEnabled = true
        progressiveTranscriptionError = nil
        progressiveTranscriptionActivity = .extractingAudio
        restartProgressiveTranscription(at: playbackState.currentTime)
    }

    func playbackPositionDidJump() {
        restartProgressiveTranscriptionIfNeeded()
    }

    private func restartProgressiveTranscriptionIfNeeded() {
        guard isProgressiveTranscriptionEnabled else { return }
        restartProgressiveTranscription(at: playbackState.currentTime)
    }

    private func restartProgressiveTranscription(at time: TimeInterval) {
        guard let videoURL = currentURL else { return }
        progressiveTranscriptionTask?.cancel()

        let locale = Locale(identifier: selectedTranscriptionLocaleIdentifier)
        let operationID = UUID()
        let trackID = progressiveTrackID ?? UUID()
        progressiveTranscriptionID = operationID
        progressiveTrackID = trackID

        if let index = subtitleTracks.firstIndex(where: { $0.id == trackID }) {
            subtitleTracks[index].cues.removeAll { $0.startTime >= time }
        } else {
            subtitleTracks.append(
                SubtitleTrack(
                    id: trackID,
                    name: "Live • \(localeName(locale))",
                    cues: [],
                    isEnabled: subtitleTracks.filter(\.isEnabled).count < 2
                )
            )
        }

        progressiveTranscriptionTask = Task { [weak self, transcriptionEngine] in
            do {
                let stream = transcriptionEngine.progressiveTranscription(
                    audioAt: videoURL,
                    locale: locale,
                    trackID: trackID,
                    startingAt: time,
                    progress: { [weak self] activity in
                        Task { @MainActor in
                            guard let self, self.progressiveTranscriptionID == operationID else { return }
                            self.progressiveTranscriptionActivity = activity
                        }
                    }
                )
                for try await cue in stream {
                    try Task.checkCancellation()
                    guard let self, progressiveTranscriptionID == operationID,
                          let index = subtitleTracks.firstIndex(where: { $0.id == trackID }) else {
                        return
                    }
                    subtitleTracks[index].cues.append(cue)
                }
                guard let self, progressiveTranscriptionID == operationID else { return }
                progressiveTranscriptionTask = nil
                progressiveTranscriptionActivity = nil
            } catch is CancellationError {
                return
            } catch {
                guard let self, progressiveTranscriptionID == operationID else { return }
                progressiveTranscriptionTask = nil
                progressiveTranscriptionID = nil
                isProgressiveTranscriptionEnabled = false
                progressiveTranscriptionActivity = nil
                progressiveTranscriptionError = error.localizedDescription
            }
        }
    }

    private func finishTranscription(_ operationID: UUID, with status: TranscriptionStatus) {
        guard transcriptionID == operationID else { return }
        transcriptionTask = nil
        transcriptionID = nil
        transcriptionStatus = status
        transcriptionActivity = nil
    }

    var languageAssetDownloadProgress: Double? {
        if case .preparingLanguage(let progress) = transcriptionActivity {
            return progress
        }
        if case .preparingLanguage(let progress) = progressiveTranscriptionActivity {
            return progress
        }
        return nil
    }

    func cancelLanguageAssetPreparation() {
        if transcriptionStatus.isRunning {
            cancelTranscription()
        }
        if isProgressiveTranscriptionEnabled {
            setProgressiveTranscriptionEnabled(false)
        }
    }

    func localeName(_ locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    private static func loadSubtitleStyles(from userDefaults: UserDefaults) -> [SubtitleStyle] {
        guard let data = userDefaults.data(forKey: subtitleStylesKey),
              let styles = try? JSONDecoder().decode([SubtitleStyle].self, from: data),
              styles.count == 2 else {
            return [.primary, .secondary]
        }
        return styles.map { $0.normalized() }
    }

    private func saveSubtitleStyles() {
        guard let data = try? JSONEncoder().encode(subtitleStyles) else { return }
        userDefaults.set(data, forKey: Self.subtitleStylesKey)
    }

    private static func loadSubtitleStyleProfiles(from userDefaults: UserDefaults) -> [SubtitleStyleProfile] {
        guard let data = userDefaults.data(forKey: subtitleStyleProfilesKey),
              let profiles = try? JSONDecoder().decode([SubtitleStyleProfile].self, from: data) else {
            return []
        }
        return profiles.filter { $0.styles.count == 2 }
    }

    private func saveSubtitleStyleProfiles() {
        guard let data = try? JSONEncoder().encode(subtitleStyleProfiles) else { return }
        userDefaults.set(data, forKey: Self.subtitleStyleProfilesKey)
    }
}
