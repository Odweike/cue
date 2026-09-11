import Foundation
import Observation

@MainActor
@Observable
final class PlayerViewModel {
    private static let subtitleStylesKey = "SubtitleStyles"
    private static let subtitleStyleProfilesKey = "SubtitleStyleProfiles"
    private static let transcriptionLocaleKey = "TranscriptionLocale"

    let playbackEngine: any PlaybackEngine
    private var transcriptionEngine: any TranscriptionEngine
    private let subtitleExtractor = SubtitleExtractor()
    private let userDefaults: UserDefaults
    private var transcriptionTask: Task<Void, Never>?
    private var transcriptionID: UUID?
    private var progressiveTranscriptionTask: Task<Void, Never>?
    private var progressiveTranscriptionID: UUID?
    private var progressiveTrackID: UUID?
    private var accessedFileURL: URL?
    private var mediaLoadID = UUID()
    private var subtitleLoadTask: Task<Void, Never>?
    private var embeddedSubtitleTasks: [Task<Void, Never>] = []
    private var embeddedSubtitlesLoadedID: UUID?
    private var pendingResumePosition: TimeInterval?
    private let watchHistory: WatchHistoryStore
    private var lastHistorySave = Date.distantPast
    private var lastScrubSeek = Date.distantPast
    private(set) var currentURL: URL?
    private(set) var playbackError: String?
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false
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
    private(set) var isSettingsPresented = false
    private(set) var isScrubbing = false
    private(set) var scrubTime: TimeInterval = 0
    private(set) var continueWatching: [WatchHistoryItem] = []

    init(
        playbackEngine: any PlaybackEngine,
        transcriptionEngine: any TranscriptionEngine = AppleSpeechTranscriptionEngine(),
        userDefaults: UserDefaults = .standard,
        watchHistory: WatchHistoryStore = .ephemeral()
    ) {
        self.playbackEngine = playbackEngine
        self.transcriptionEngine = transcriptionEngine
        self.userDefaults = userDefaults
        self.watchHistory = watchHistory
        subtitleStyles = Self.loadSubtitleStyles(from: userDefaults)
        subtitleStyleProfiles = Self.loadSubtitleStyleProfiles(from: userDefaults)
        selectedTranscriptionLocaleIdentifier = userDefaults.string(
            forKey: Self.transcriptionLocaleKey
        ) ?? Locale.current.identifier
        continueWatching = watchHistory.unfinished()

        self.playbackEngine.eventHandler = { [weak self] event in
            self?.handleEngineEvent(event)
        }
    }

    func open(_ url: URL, resumingAt position: TimeInterval? = nil) {
        let fileURL = url.resolvingSymlinksInPath().standardizedFileURL
        persistWatchProgress()
        if currentURL == fileURL {
            if let position, position > 1 {
                seek(to: position)
            }
            return
        }

        teardownCurrentFile()
        accessedFileURL = fileURL.startAccessingSecurityScopedResource() ? fileURL : nil

        playbackEngine.open(fileURL)
        playbackEngine.play()
        currentURL = fileURL
        if let position, position > 1 {
            pendingResumePosition = position
        }
        refreshPlaybackState()
        refreshAudioTracks()
        startSubtitleLoad(for: fileURL)
        persistWatchProgress(force: true)
    }

    private func teardownCurrentFile() {
        cancelTranscription()
        setProgressiveTranscriptionEnabled(false)
        subtitleLoadTask?.cancel()
        subtitleLoadTask = nil
        embeddedSubtitleTasks.forEach { $0.cancel() }
        embeddedSubtitleTasks.removeAll()
        embeddedSubtitlesLoadedID = nil
        pendingResumePosition = nil
        subtitleTracks.removeAll()
        audioTracks.removeAll()
        isScrubbing = false
        mediaLoadID = UUID()
        accessedFileURL?.stopAccessingSecurityScopedResource()
        accessedFileURL = nil
    }

    private func handleEngineEvent(_ event: PlaybackEngineEvent) {
        guard playbackEngine.currentURL == currentURL else { return }
        switch event {
        case .fileReady:
            refreshPlaybackState()
            refreshAudioTracks()
            resumePendingPositionIfNeeded()
            loadEmbeddedSubtitleStreams()
        case .failedToOpen(let message):
            if let failedURL = currentURL {
                watchHistory.remove(failedURL.path)
            }
            teardownCurrentFile()
            currentURL = nil
            refreshPlaybackState()
            continueWatching = watchHistory.unfinished()
            playbackError = message
        }
    }

    func dismissPlaybackError() {
        playbackError = nil
    }

    private func resumePendingPositionIfNeeded() {
        guard let position = pendingResumePosition else { return }
        pendingResumePosition = nil
        seek(to: duration > 1 ? min(position, duration - 1) : position)
        persistWatchProgress(force: true)
    }

    func resumeWatching(_ item: WatchHistoryItem) {
        guard let url = watchHistory.resolve(item) else {
            forgetWatchHistory(item.id)
            return
        }
        open(url, resumingAt: item.position)
    }

    func forgetWatchHistory(_ id: String) {
        watchHistory.remove(id)
        continueWatching = watchHistory.unfinished()
    }

    func persistWatchProgress(force: Bool = false) {
        guard let url = currentURL else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastHistorySave) < 2 { return }
        lastHistorySave = now
        watchHistory.upsert(url: url, position: currentTime, duration: duration)
        continueWatching = watchHistory.unfinished()
    }

    func refreshPlaybackState() {
        let state = playbackEngine.state
        if !isScrubbing {
            currentTime = state.currentTime
            duration = state.duration
            isPlaying = state.isPlaying
        }
        if !state.hasSameControls(as: playbackState) {
            playbackState = state
        }
        persistWatchProgress()
    }

    func togglePlayback() {
        if isPlaying {
            playbackEngine.pause()
        } else {
            playbackEngine.play()
        }
        refreshPlaybackState()
        persistWatchProgress(force: true)
    }

    func seek(to time: TimeInterval) {
        playbackEngine.seek(to: time, exact: true)
        refreshPlaybackState()
    }

    func beginScrubbing() {
        guard !isScrubbing else { return }
        isScrubbing = true
        scrubTime = currentTime
    }

    func updateScrubbing(to time: TimeInterval) {
        if !isScrubbing {
            isScrubbing = true
        }
        scrubTime = time
        let now = Date()
        guard now.timeIntervalSince(lastScrubSeek) >= 0.05 else { return }
        lastScrubSeek = now
        playbackEngine.seek(to: time, exact: false)
    }

    func endScrubbing() {
        playbackEngine.seek(to: scrubTime, exact: true)
        isScrubbing = false
        refreshPlaybackState()
        playbackPositionDidJump()
        persistWatchProgress(force: true)
    }

    func toggleSettingsPresented() {
        isSettingsPresented.toggle()
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
        let time = isScrubbing ? scrubTime : currentTime
        return subtitleTracks
            .filter(\.isEnabled)
            .flatMap(\.cues)
            .filter { $0.startTime <= time && time < $0.endTime }
    }

    func importSubtitles(_ url: URL) throws {
        guard let contents = SubtitleTextDecoder.string(from: url) else {
            throw SubtitleParserError.unreadableFile
        }
        try appendSubtitleTrack(
            name: url.lastPathComponent,
            contents: contents,
            fileExtension: url.pathExtension,
            autoEnable: true
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
        restartProgressiveTranscription(at: currentTime)
    }

    func playbackPositionDidJump() {
        restartProgressiveTranscriptionIfNeeded()
    }

    private func restartProgressiveTranscriptionIfNeeded() {
        guard isProgressiveTranscriptionEnabled else { return }
        restartProgressiveTranscription(at: currentTime)
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

    private func startSubtitleLoad(for fileURL: URL) {
        let loadID = mediaLoadID
        subtitleLoadTask = Task { [weak self] in
            for url in SidecarSubtitleLocator.urls(beside: fileURL) {
                guard let self, !Task.isCancelled, self.mediaLoadID == loadID else { return }
                guard let contents = SubtitleTextDecoder.string(from: url) else { continue }
                try? appendSubtitleTrack(
                    name: url.lastPathComponent,
                    contents: contents,
                    fileExtension: url.pathExtension,
                    autoEnable: true
                )
            }
        }
    }

    private func loadEmbeddedSubtitleStreams() {
        guard let fileURL = currentURL, embeddedSubtitlesLoadedID != mediaLoadID else { return }
        let streams = playbackEngine.subtitleStreams().filter(\.isTextCodec)
        guard !streams.isEmpty else { return }

        let loadID = mediaLoadID
        let sidecarTask = subtitleLoadTask
        embeddedSubtitlesLoadedID = loadID

        for stream in streams {
            let task = Task { [weak self, subtitleExtractor] in
                await sidecarTask?.value
                do {
                    let contents = try await subtitleExtractor.extract(from: fileURL, stream: stream)
                    guard let self, !Task.isCancelled, self.mediaLoadID == loadID else { return }
                    try appendSubtitleTrack(
                        name: stream.displayName,
                        contents: contents,
                        fileExtension: stream.fileExtension,
                        autoEnable: shouldAutoEnable(stream)
                    )
                } catch {
                    return
                }
            }
            embeddedSubtitleTasks.append(task)
        }
    }

    private func shouldAutoEnable(_ stream: SubtitleStream) -> Bool {
        guard !stream.isForced else { return false }
        let preferred = Locale.current.language.languageCode?.identifier.lowercased()
        if let preferred, stream.language?.lowercased().hasPrefix(preferred) == true {
            return true
        }
        return stream.isDefault
    }

    @discardableResult
    private func appendSubtitleTrack(
        name: String,
        contents: String,
        fileExtension: String,
        autoEnable: Bool
    ) throws -> Bool {
        let trackID = UUID()
        let cues = try SubtitleParser.parse(contents, fileExtension: fileExtension, trackID: trackID)
        let isEnabled = autoEnable && subtitleTracks.filter(\.isEnabled).count < 2
        subtitleTracks.append(
            SubtitleTrack(id: trackID, name: name, cues: cues, isEnabled: isEnabled)
        )
        return true
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
