import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class PlayerViewModel {
    private static let maxEnabledSubtitleTracks = 3
    private static let subtitleStylesKey = "SubtitleStyles"
    private static let subtitleStyleProfilesKey = "SubtitleStyleProfiles"
    private static let transcriptionLocaleKey = "TranscriptionLocale"

    let playbackEngine: any PlaybackEngine
    private var transcriptionEngine: any TranscriptionEngine
    private let userDefaults: UserDefaults
    private var transcriptionTask: Task<Void, Never>?
    private var transcriptionID: UUID?
    private var progressiveTranscriptionTask: Task<Void, Never>?
    private var progressiveTranscriptionID: UUID?
    private var progressiveTrackID: UUID?
    private var accessedFileURL: URL?
    private var mediaLoadID = UUID()
    private var subtitleLoadTask: Task<Void, Never>?
    private var embeddedSubtitlesLoadedID: UUID?
    private var pendingResumePosition: TimeInterval?
    private let watchHistory: WatchHistoryStore
    private var lastHistorySave = Date.distantPast
    private var lastScrubSeek = Date.distantPast
    private var skipFreezeUntil = Date.distantPast
    private var timeBeforeSkip: TimeInterval = 0
    private var transcriptionRestartTask: Task<Void, Never>?
    private var hasRestoredPlaybackSettings = false
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
    private(set) var volumeHUDPercent: Int?
    private var volumeHUDHideTask: Task<Void, Never>?
    private let nowPlaying = NowPlayingController()
    private let thumbnails = VideoThumbnailCache()
    private var lastNowPlayingSync = Date.distantPast
    private var lastNowPlayingIsPlaying: Bool?
    var pictureInPicture: PictureInPictureController?
    private(set) var isPictureInPicture = false
    private(set) var chapters: [PlaybackChapter] = []
    private(set) var loopA: TimeInterval?
    private(set) var loopB: TimeInterval?

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
        nowPlaying.attach(self)

        self.playbackEngine.eventHandler = { [weak self] event in
            self?.handleEngineEvent(event)
        }
    }

    func open(_ url: URL, resumingAt position: TimeInterval? = nil) {
        let fileURL = url.resolvingSymlinksInPath().standardizedFileURL
        persistWatchProgress(force: true)
        if currentURL == fileURL {
            if let position, position > 1 {
                seek(to: position)
            }
            return
        }

        teardownCurrentFile()
        accessedFileURL = fileURL.startAccessingSecurityScopedResource() ? fileURL : nil
        hasRestoredPlaybackSettings = false

        playbackEngine.open(fileURL)
        playbackEngine.play()
        currentURL = fileURL
        let resumeAt = position ?? watchHistory.item(for: fileURL)?.position
        if let resumeAt, resumeAt > 1 {
            pendingResumePosition = resumeAt
        }
        refreshPlaybackState(includingControls: true)
        refreshAudioTracks()
        startSubtitleLoad(for: fileURL)
    }

    private func teardownCurrentFile() {
        cancelTranscription()
        setProgressiveTranscriptionEnabled(false)
        subtitleLoadTask?.cancel()
        subtitleLoadTask = nil
        embeddedSubtitlesLoadedID = nil
        pendingResumePosition = nil
        subtitleTracks.removeAll()
        audioTracks.removeAll()
        isScrubbing = false
        mediaLoadID = UUID()
        accessedFileURL?.stopAccessingSecurityScopedResource()
        accessedFileURL = nil
        hasRestoredPlaybackSettings = false
        chapters = []
        loopA = nil
        loopB = nil
        thumbnails.cancel()
        nowPlaying.stop()
        SleepPreventer.update(isPlaying: false)
        pictureInPicture?.exitIfNeeded()
        playbackEngine.clearABLoop()
    }

    private func handleEngineEvent(_ event: PlaybackEngineEvent) {
        guard playbackEngine.currentURL == currentURL else { return }
        switch event {
        case .fileReady:
            refreshPlaybackState(includingControls: true)
            refreshAudioTracks()
            restorePlaybackSettingsIfNeeded()
            resumePendingPositionIfNeeded()
            loadEmbeddedSubtitleStreams()
            chapters = playbackEngine.chapters()
            if let url = currentURL {
                nowPlaying.start(title: url.lastPathComponent)
                thumbnails.prepare(url: url, duration: duration)
            }
        case .tracksChanged:
            refreshAudioTracks()
            loadEmbeddedSubtitleStreams()
        case .failedToOpen(let message):
            if let failedURL = currentURL {
                watchHistory.remove(failedURL.path)
            }
            teardownCurrentFile()
            currentURL = nil
            refreshPlaybackState(includingControls: true)
            continueWatching = watchHistory.unfinished()
            playbackError = message
        }
    }

    func dismissPlaybackError() {
        playbackError = nil
    }

    private func resumePendingPositionIfNeeded() {
        guard let position = pendingResumePosition else { return }
        let target = duration > 1 ? min(position, duration - 1) : position
        playbackEngine.seek(to: target, exact: true)
        currentTime = target
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
        if !force {
            guard pendingResumePosition == nil, hasRestoredPlaybackSettings else { return }
        } else {
            guard hasRestoredPlaybackSettings || pendingResumePosition != nil || currentTime > 1 else {
                return
            }
        }
        let now = Date()
        if !force, now.timeIntervalSince(lastHistorySave) < 2 { return }
        lastHistorySave = now
        watchHistory.upsert(
            url: url,
            position: pendingResumePosition ?? currentTime,
            duration: duration,
            settings: currentPlaybackSettings()
        )
        continueWatching = watchHistory.unfinished()
    }

    func refreshPlaybackState(includingControls: Bool = false) {
        let clock = playbackEngine.playbackClock()
        if let pending = pendingResumePosition, pending > 1 {
            duration = clock.duration
            isPlaying = clock.isPlaying
            let target = duration > 1 ? min(pending, duration - 1) : pending
            if clock.time > 1, abs(clock.time - target) < 4 {
                pendingResumePosition = nil
                currentTime = clock.time
            } else {
                currentTime = target
            }
        } else if !isScrubbing {
            let seekHasLanded = Date() >= skipFreezeUntil
                || abs(clock.time - timeBeforeSkip) >= 1
            if seekHasLanded {
                currentTime = clock.time
                duration = clock.duration
                isPlaying = clock.isPlaying
            }
        }
        if includingControls {
            let state = playbackEngine.state
            if !state.hasSameControls(as: playbackState) {
                playbackState = state
            }
        }
        persistWatchProgress()
        syncNowPlayingAndSleep()
    }

    private func syncNowPlayingAndSleep() {
        SleepPreventer.update(isPlaying: isPlaying && currentURL != nil)
        guard let url = currentURL else { return }
        let now = Date()
        if lastNowPlayingIsPlaying == isPlaying, now.timeIntervalSince(lastNowPlayingSync) < 1 {
            return
        }
        lastNowPlayingSync = now
        lastNowPlayingIsPlaying = isPlaying
        nowPlaying.update(
            title: url.lastPathComponent,
            time: currentTime,
            duration: duration,
            isPlaying: isPlaying,
            rate: playbackState.playbackRate
        )
        pictureInPicture?.syncPlaying(isPlaying)
    }

    func togglePlayback() {
        if isPlaying {
            playbackEngine.pause()
        } else {
            playbackEngine.play()
        }
        refreshPlaybackState(includingControls: true)
        persistWatchProgress(force: true)
    }

    func playIfNeeded() {
        guard !isPlaying else { return }
        togglePlayback()
    }

    func pauseIfNeeded() {
        guard isPlaying else { return }
        togglePlayback()
    }

    func cycleABLoop() {
        playbackEngine.cycleABLoop(at: currentTime)
        loopA = playbackEngine.loopA
        loopB = playbackEngine.loopB
    }

    func thumbnail(at time: TimeInterval) -> NSImage? {
        thumbnails.image(at: time)
    }

    func togglePictureInPicture() {
        pictureInPicture?.toggle()
    }

    func setPictureInPicture(_ active: Bool) {
        isPictureInPicture = active
    }

    func seek(to time: TimeInterval) {
        playbackEngine.seek(to: time, exact: true)
        refreshPlaybackState(includingControls: true)
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
        refreshPlaybackState(includingControls: true)
        playbackPositionDidJump()
        persistWatchProgress(force: true)
    }

    func toggleSettingsPresented() {
        isSettingsPresented.toggle()
    }

    func skip(by interval: TimeInterval) {
        timeBeforeSkip = currentTime
        let target = max(currentTime + interval, 0)
        playbackEngine.skip(by: interval)
        currentTime = duration > 0 ? min(target, duration) : target
        skipFreezeUntil = Date().addingTimeInterval(0.08)
        restartProgressiveTranscriptionIfNeeded()
    }

    func nudgeVolume(by delta: Float) {
        if delta > 0, playbackState.isMuted {
            setMuted(false)
        }
        setVolume(min(max(playbackState.volume + delta, 0), 1))
        volumeHUDPercent = Int((playbackState.volume * 100).rounded())
        volumeHUDHideTask?.cancel()
        volumeHUDHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.volumeHUDPercent = nil
        }
    }

    func setVolume(_ volume: Float) {
        playbackEngine.setVolume(volume)
        refreshPlaybackState(includingControls: true)
    }

    func setMuted(_ isMuted: Bool) {
        playbackEngine.setMuted(isMuted)
        refreshPlaybackState(includingControls: true)
    }

    func toggleMuted() {
        setMuted(!playbackState.isMuted)
    }

    func setPlaybackRate(_ rate: Float) {
        playbackEngine.setPlaybackRate(rate)
        refreshPlaybackState(includingControls: true)
    }

    func setVideoScalingMode(_ mode: VideoScalingMode) {
        playbackEngine.setVideoScalingMode(mode)
        refreshPlaybackState(includingControls: true)
    }

    func setAspectRatio(_ ratio: VideoRatio) {
        playbackEngine.setAspectRatio(ratio)
        refreshPlaybackState(includingControls: true)
    }

    func setCropRatio(_ ratio: VideoRatio) {
        playbackEngine.setCropRatio(ratio)
        refreshPlaybackState(includingControls: true)
    }

    func setRotation(_ rotation: VideoRotation) {
        playbackEngine.setRotation(rotation)
        refreshPlaybackState(includingControls: true)
    }

    func setHardwareDecoding(_ isEnabled: Bool) {
        playbackEngine.setHardwareDecoding(isEnabled)
        refreshPlaybackState(includingControls: true)
    }

    func setDeinterlacing(_ isEnabled: Bool) {
        playbackEngine.setDeinterlacing(isEnabled)
        refreshPlaybackState(includingControls: true)
    }

    func setVideoEqualizer(_ equalizer: VideoEqualizer) {
        playbackEngine.setVideoEqualizer(equalizer)
        refreshPlaybackState(includingControls: true)
    }

    func refreshAudioTracks() {
        audioTracks = playbackEngine.audioTracks()
    }

    func selectAudioTrack(_ id: Int64) {
        playbackEngine.selectAudioTrack(id)
        refreshAudioTracks()
        persistWatchProgress(force: true)
    }

    private func currentPlaybackSettings() -> VideoPlaybackSettings {
        let track = audioTracks.first(where: \.isSelected)
        return VideoPlaybackSettings(
            audioTrackID: track?.id,
            audioLanguage: track?.language,
            volume: playbackState.volume,
            isMuted: playbackState.isMuted,
            playbackRate: playbackState.playbackRate,
            audioDelay: playbackState.audioDelay,
            subtitleDelay: playbackState.subtitleDelay,
            videoScalingMode: playbackState.videoScalingMode,
            aspectRatio: playbackState.aspectRatio,
            cropRatio: playbackState.cropRatio,
            rotation: playbackState.rotation,
            hardwareDecoding: playbackState.hardwareDecoding,
            deinterlacing: playbackState.deinterlacing,
            videoEqualizer: playbackState.videoEqualizer
        )
    }

    private func restorePlaybackSettingsIfNeeded() {
        guard !hasRestoredPlaybackSettings, let url = currentURL else { return }
        hasRestoredPlaybackSettings = true
        guard let settings = watchHistory.item(for: url)?.settings else { return }
        if let volume = settings.volume { setVolume(volume) }
        if let isMuted = settings.isMuted { setMuted(isMuted) }
        if let playbackRate = settings.playbackRate { setPlaybackRate(playbackRate) }
        if let audioDelay = settings.audioDelay { setAudioDelay(audioDelay) }
        if let subtitleDelay = settings.subtitleDelay { setSubtitleDelay(subtitleDelay) }
        if let videoScalingMode = settings.videoScalingMode { setVideoScalingMode(videoScalingMode) }
        if let aspectRatio = settings.aspectRatio { setAspectRatio(aspectRatio) }
        if let cropRatio = settings.cropRatio { setCropRatio(cropRatio) }
        if let rotation = settings.rotation { setRotation(rotation) }
        if let hardwareDecoding = settings.hardwareDecoding { setHardwareDecoding(hardwareDecoding) }
        if let deinterlacing = settings.deinterlacing { setDeinterlacing(deinterlacing) }
        if let videoEqualizer = settings.videoEqualizer { setVideoEqualizer(videoEqualizer) }
        if let track = settings.matchingAudioTrack(in: audioTracks) {
            selectAudioTrack(track.id)
        }
    }

    func setAudioDelay(_ delay: TimeInterval) {
        playbackEngine.setAudioDelay(delay)
        refreshPlaybackState(includingControls: true)
    }

    func setSubtitleDelay(_ delay: TimeInterval) {
        playbackEngine.setSubtitleDelay(delay)
        refreshPlaybackState(includingControls: true)
    }

    var visibleSubtitleCues: [SubtitleCue] {
        let time = (isScrubbing ? scrubTime : currentTime) - playbackState.subtitleDelay
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
        if enabled, subtitleTracks.filter(\.isEnabled).count >= Self.maxEnabledSubtitleTracks { return }
        subtitleTracks[index].isEnabled = enabled
        syncMpvSubtitles()
    }

    func subtitleStyle(for trackID: UUID) -> SubtitleStyle {
        let enabledTracks = subtitleTracks.filter(\.isEnabled)
        guard let index = enabledTracks.firstIndex(where: { $0.id == trackID }) else {
            return .primary
        }
        var style = subtitleStyles[min(index, subtitleStyles.count - 1)]
        if style.position != .custom {
            let stack = enabledTracks.enumerated().prefix(index).reduce(0) { count, item in
                let other = subtitleStyles[min(item.offset, subtitleStyles.count - 1)]
                let sameEdge = (style.position == .top) == (other.position == .top)
                return count + (sameEdge ? 1 : 0)
            }
            style.verticalOffset = 60 + Double(stack) * 52
        }
        return style
    }

    func setSubtitleStyle(_ style: SubtitleStyle, at index: Int) {
        guard subtitleStyles.indices.contains(index) else { return }
        subtitleStyles[index] = style.normalized()
        saveSubtitleStyles()
        syncMpvSubtitles()
    }

    func resetSubtitleStyle(at index: Int) {
        guard SubtitleStyle.defaults.indices.contains(index) else { return }
        setSubtitleStyle(SubtitleStyle.defaults[index], at: index)
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
              profile.styles.count >= 2 else { return }
        subtitleStyles = SubtitleStyle.padded(profile.styles)
        saveSubtitleStyles()
        syncMpvSubtitles()
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
                let isEnabled = subtitleTracks.filter(\.isEnabled).count < Self.maxEnabledSubtitleTracks
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
        transcriptionRestartTask?.cancel()
        transcriptionRestartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.restartProgressiveTranscription(at: self.currentTime)
        }
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
                    isEnabled: subtitleTracks.filter(\.isEnabled).count < Self.maxEnabledSubtitleTracks
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
        guard embeddedSubtitlesLoadedID != mediaLoadID else { return }
        let streams = playbackEngine.subtitleStreams()
        guard !streams.isEmpty else { return }
        embeddedSubtitlesLoadedID = mediaLoadID
        for stream in streams {
            let isEnabled = shouldAutoEnable(stream) && subtitleTracks.filter(\.isEnabled).count < Self.maxEnabledSubtitleTracks
            subtitleTracks.append(
                SubtitleTrack(
                    id: UUID(),
                    name: stream.displayName,
                    cues: [],
                    isEnabled: isEnabled,
                    mpvID: stream.id
                )
            )
        }
        syncMpvSubtitles()
    }

    private func syncMpvSubtitles() {
        // ponytail: mpv only has sid + secondary-sid, so the 3rd enabled track
        // renders in the overlay when it has cues.
        let enabled = subtitleTracks.filter(\.isEnabled)
        let mpv = enabled.compactMap { track -> (Int64, SubtitleStyle)? in
            guard let id = track.mpvID else { return nil }
            return (id, subtitleStyle(for: track.id))
        }
        playbackEngine.selectSubtitleTracks(
            primary: mpv.first?.0,
            secondary: mpv.dropFirst().first?.0,
            primaryTop: mpv.first?.1.position == .top,
            secondaryTop: mpv.dropFirst().first?.1.position == .top
        )
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
        let isEnabled = autoEnable && subtitleTracks.filter(\.isEnabled).count < Self.maxEnabledSubtitleTracks
        subtitleTracks.append(
            SubtitleTrack(id: trackID, name: name, cues: cues, isEnabled: isEnabled)
        )
        return true
    }

    private static func loadSubtitleStyles(from userDefaults: UserDefaults) -> [SubtitleStyle] {
        guard let data = userDefaults.data(forKey: subtitleStylesKey),
              let styles = try? JSONDecoder().decode([SubtitleStyle].self, from: data),
              styles.count >= 2 else {
            return SubtitleStyle.defaults
        }
        return SubtitleStyle.padded(styles)
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
        return profiles.compactMap { profile in
            guard profile.styles.count >= 2 else { return nil }
            var profile = profile
            profile.styles = SubtitleStyle.padded(profile.styles)
            return profile
        }
    }

    private func saveSubtitleStyleProfiles() {
        guard let data = try? JSONEncoder().encode(subtitleStyleProfiles) else { return }
        userDefaults.set(data, forKey: Self.subtitleStyleProfilesKey)
    }
}
