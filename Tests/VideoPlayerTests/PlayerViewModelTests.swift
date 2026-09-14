import AppKit
import AVFAudio
import XCTest
@testable import VideoPlayer

@MainActor
final class PlayerViewModelTests: XCTestCase {
    func testAudioExtractorWithOptionalLocalVideo() async throws {
        guard let path = ProcessInfo.processInfo.environment["CUE_TEST_VIDEO"] else {
            throw XCTSkip("Set CUE_TEST_VIDEO to run the local media integration test")
        }
        let outputURL = try await AudioExtractor().extract(
            from: URL(fileURLWithPath: path),
            duration: 2
        )
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let audioFile = try AVAudioFile(forReading: outputURL)
        XCTAssertGreaterThan(audioFile.length, 0)
        XCTAssertEqual(audioFile.processingFormat.channelCount, 1)
    }

    func testOpeningVideoUpdatesEngineAndViewModel() {
        let engine = PlaybackEngineSpy()
        let viewModel = PlayerViewModel(playbackEngine: engine)
        let url = URL(fileURLWithPath: "/tmp/example.mp4")

        viewModel.open(url)

        XCTAssertEqual(engine.currentURL, url)
        XCTAssertEqual(viewModel.currentURL, url)
        XCTAssertTrue(viewModel.isPlaying)

        viewModel.open(url)
        XCTAssertEqual(engine.openCount, 1)
    }

    func testVideoFileValidationAcceptsMoviesAndRejectsOtherFiles() {
        XCTAssertTrue(VideoFilePicker.canOpen(URL(fileURLWithPath: "/tmp/movie.mkv")))
        XCTAssertTrue(VideoFilePicker.canOpen(URL(fileURLWithPath: "/tmp/movie.mp4")))
        XCTAssertFalse(VideoFilePicker.canOpen(URL(fileURLWithPath: "/tmp/notes.txt")))
        XCTAssertFalse(VideoFilePicker.canOpen(URL(string: "https://example.com/movie.mp4")!))
    }

    func testControlsAreForwardedToPlaybackEngine() {
        let engine = PlaybackEngineSpy()
        let viewModel = PlayerViewModel(playbackEngine: engine)

        viewModel.setVolume(0.4)
        viewModel.setMuted(true)
        viewModel.setPlaybackRate(1.5)
        viewModel.setVideoScalingMode(.fill)
        viewModel.setAspectRatio(.ratio16x9)
        viewModel.setCropRatio(.ratio4x3)
        viewModel.setRotation(.degrees90)
        viewModel.setHardwareDecoding(false)
        viewModel.setDeinterlacing(true)
        viewModel.setVideoEqualizer(VideoEqualizer(brightness: 10, contrast: -5))
        viewModel.setAudioDelay(0.4)
        viewModel.seek(to: 42)
        viewModel.skip(by: 10)

        XCTAssertEqual(engine.volume, 0.4)
        XCTAssertEqual(engine.isMuted, true)
        XCTAssertEqual(engine.playbackRate, 1.5)
        XCTAssertEqual(engine.videoScalingMode, .fill)
        XCTAssertEqual(engine.aspectRatio, .ratio16x9)
        XCTAssertEqual(engine.cropRatio, .ratio4x3)
        XCTAssertEqual(engine.rotation, .degrees90)
        XCTAssertEqual(engine.hardwareDecoding, false)
        XCTAssertEqual(engine.deinterlacing, true)
        XCTAssertEqual(engine.videoEqualizer, VideoEqualizer(brightness: 10, contrast: -5))
        XCTAssertEqual(engine.audioDelay, 0.4)
        XCTAssertEqual(engine.seekTime, 42)
        XCTAssertEqual(engine.skipInterval, 10)
        XCTAssertEqual(viewModel.currentTime, 10)
    }

    func testScrubbingSeeksWithKeyframesUntilRelease() {
        let engine = PlaybackEngineSpy()
        let viewModel = PlayerViewModel(playbackEngine: engine)

        viewModel.updateScrubbing(to: 80)
        XCTAssertEqual(engine.seekTime, 80)
        XCTAssertEqual(engine.seekExact, false)

        viewModel.endScrubbing()
        XCTAssertEqual(engine.seekExact, true)
    }

    func testABLoopCyclesFromAToBThenClears() {
        let engine = PlaybackEngineSpy()
        engine.state.currentTime = 12
        let viewModel = PlayerViewModel(playbackEngine: engine)
        viewModel.refreshPlaybackState()

        viewModel.cycleABLoop()
        XCTAssertEqual(engine.loopA, 12)
        XCTAssertNil(engine.loopB)

        engine.state.currentTime = 40
        viewModel.refreshPlaybackState()
        viewModel.cycleABLoop()
        XCTAssertEqual(engine.loopA, 12)
        XCTAssertEqual(engine.loopB, 40)

        viewModel.cycleABLoop()
        XCTAssertNil(engine.loopA)
        XCTAssertNil(engine.loopB)
    }

    func testMuteTogglePreservesVolume() {
        let engine = PlaybackEngineSpy()
        engine.state.volume = 0.4
        let viewModel = PlayerViewModel(playbackEngine: engine)
        viewModel.refreshPlaybackState(includingControls: true)

        viewModel.toggleMuted()

        XCTAssertTrue(viewModel.playbackState.isMuted)
        XCTAssertEqual(viewModel.playbackState.volume, 0.4)

        viewModel.toggleMuted()

        XCTAssertFalse(viewModel.playbackState.isMuted)
        XCTAssertEqual(viewModel.playbackState.volume, 0.4)
    }

    func testNudgeVolumeShowsPercentHUD() {
        let engine = PlaybackEngineSpy()
        engine.state.volume = 0.4
        let viewModel = PlayerViewModel(playbackEngine: engine)
        viewModel.refreshPlaybackState(includingControls: true)

        viewModel.nudgeVolume(by: 0.05)

        XCTAssertEqual(engine.volume, 0.45)
        XCTAssertEqual(viewModel.volumeHUDPercent, 45)
    }

    func testAudioTracksCanBeLoadedAndSelected() {
        let engine = PlaybackEngineSpy()
        engine.availableAudioTracks = [
            AudioTrack(
                id: 2,
                title: "Original",
                language: "eng",
                codec: "aac",
                channelCount: 6,
                isSelected: true
            )
        ]
        let viewModel = PlayerViewModel(playbackEngine: engine)

        viewModel.refreshAudioTracks()
        viewModel.selectAudioTrack(2)

        XCTAssertEqual(
            viewModel.audioTracks.first?.displayName(locale: Locale(identifier: "en_US")),
            "English • Original • 6 ch"
        )
        XCTAssertEqual(engine.selectedAudioTrackID, 2)
        XCTAssertEqual(
            AudioTrack(
                id: 1,
                title: "MOV",
                language: "jpn",
                codec: "aac",
                channelCount: 2,
                isSelected: false
            ).displayName(locale: Locale(identifier: "en_US")),
            "Japanese • 2 ch"
        )
    }

    func testSubtitleStylesPersistBetweenViewModels() {
        let suiteName = "PlayerViewModelTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let style = SubtitleStyle(
            fontSize: 36,
            fontDesign: .rounded,
            fontWeight: .bold,
            textColor: .cyan,
            outlineColor: .blue,
            outlineWidth: 2,
            backgroundColor: .red,
            backgroundOpacity: 0.4,
            position: .top,
            verticalOffset: 210,
            alignment: .leading
        )

        let firstViewModel = PlayerViewModel(
            playbackEngine: PlaybackEngineSpy(),
            userDefaults: userDefaults
        )
        firstViewModel.setSubtitleStyle(style, at: 1)
        let restoredViewModel = PlayerViewModel(
            playbackEngine: PlaybackEngineSpy(),
            userDefaults: userDefaults
        )

        XCTAssertEqual(restoredViewModel.subtitleStyles[1], style)
    }

    func testLegacySubtitleStyleKeepsItsSavedHeight() throws {
        let data = Data(#"{"fontSize":30,"textColor":"white","backgroundOpacity":0.5,"bottomPadding":210}"#.utf8)

        let style = try JSONDecoder().decode(SubtitleStyle.self, from: data)

        XCTAssertEqual(style.verticalOffset, 210)
        XCTAssertEqual(style.position, .custom)
        XCTAssertEqual(style.fontWeight, .semibold)
    }

    func testSubtitleStyleProfilesPersistAndApplyBothTracks() {
        let suiteName = "PlayerViewModelTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let viewModel = PlayerViewModel(
            playbackEngine: PlaybackEngineSpy(),
            userDefaults: userDefaults
        )
        var first = SubtitleStyle.primary
        first.fontSize = 40
        var second = SubtitleStyle.secondary
        second.position = .top
        viewModel.setSubtitleStyle(first, at: 0)
        viewModel.setSubtitleStyle(second, at: 1)

        XCTAssertTrue(viewModel.saveSubtitleStyleProfile(named: "Cinema"))
        viewModel.resetSubtitleStyle(at: 0)
        viewModel.resetSubtitleStyle(at: 1)
        viewModel.applySubtitleStyleProfile(viewModel.subtitleStyleProfiles[0].id)
        let restored = PlayerViewModel(
            playbackEngine: PlaybackEngineSpy(),
            userDefaults: userDefaults
        )

        XCTAssertEqual(viewModel.subtitleStyles, [first, second])
        XCTAssertEqual(restored.subtitleStyleProfiles.first?.name, "Cinema")
        XCTAssertEqual(restored.subtitleStyleProfiles.first?.styles, [first, second])
    }

    func testFileReadyResumesPendingPosition() {
        let engine = PlaybackEngineSpy()
        let viewModel = PlayerViewModel(playbackEngine: engine)

        viewModel.open(URL(fileURLWithPath: "/tmp/example.mp4"), resumingAt: 42)
        engine.state.duration = 100
        engine.eventHandler?(.fileReady)

        XCTAssertEqual(engine.seekTime, 42)
        XCTAssertEqual(engine.seekExact, true)
    }

    func testOpeningTheSameFileFromFinderResumesSavedPosition() {
        let historyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: historyURL) }
        let video = URL(fileURLWithPath: "/tmp/movie.mkv")
        let store = WatchHistoryStore(fileURL: historyURL)
        store.upsert(url: video, position: 80, duration: 120)

        let engine = PlaybackEngineSpy()
        let viewModel = PlayerViewModel(playbackEngine: engine, watchHistory: store)
        viewModel.open(video)
        engine.state.duration = 120
        engine.eventHandler?(.fileReady)

        XCTAssertEqual(engine.seekTime, 80)
        XCTAssertEqual(store.item(for: video)?.position, 80)
    }

    func testFailedToOpenReturnsToWelcomeWithError() {
        let engine = PlaybackEngineSpy()
        let viewModel = PlayerViewModel(playbackEngine: engine)
        let url = URL(fileURLWithPath: "/tmp/broken.mp4").resolvingSymlinksInPath().standardizedFileURL

        viewModel.open(url)
        XCTAssertEqual(viewModel.currentURL, url)

        engine.eventHandler?(.failedToOpen("boom"))

        XCTAssertNil(viewModel.currentURL)
        XCTAssertEqual(viewModel.playbackError, "boom")
        XCTAssertTrue(viewModel.continueWatching.isEmpty)

        viewModel.dismissPlaybackError()
        XCTAssertNil(viewModel.playbackError)
    }

    func testProgressiveTranscriptionAddsCuesAsTheyArrive() async {
        let viewModel = PlayerViewModel(
            playbackEngine: PlaybackEngineSpy(),
            transcriptionEngine: TranscriptionEngineStub()
        )
        viewModel.open(URL(fileURLWithPath: "/tmp/example.mp4"))
        await viewModel.loadSupportedTranscriptionLocales()

        viewModel.setProgressiveTranscriptionEnabled(true)
        for _ in 0..<20 where viewModel.subtitleTracks.first?.cues.isEmpty != false {
            await Task.yield()
        }

        XCTAssertTrue(viewModel.isProgressiveTranscriptionEnabled)
        XCTAssertEqual(viewModel.subtitleTracks.first?.cues.first?.text, "Live cue")

        viewModel.setProgressiveTranscriptionEnabled(false)
        XCTAssertFalse(viewModel.isProgressiveTranscriptionEnabled)
        XCTAssertTrue(viewModel.subtitleTracks.isEmpty)
    }

    func testLanguageAssetProgressIsExposedAndCanBeCancelled() async {
        let viewModel = PlayerViewModel(
            playbackEngine: PlaybackEngineSpy(),
            transcriptionEngine: TranscriptionEngineStub()
        )
        viewModel.open(URL(fileURLWithPath: "/tmp/example.mp4"))
        await viewModel.loadSupportedTranscriptionLocales()

        viewModel.startTranscription()
        for _ in 0..<20 where viewModel.languageAssetDownloadProgress == nil {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.languageAssetDownloadProgress, 0.5)
        viewModel.cancelLanguageAssetPreparation()
        XCTAssertFalse(viewModel.transcriptionStatus.isRunning)
        XCTAssertNil(viewModel.languageAssetDownloadProgress)
    }
}

private struct TranscriptionEngineStub: TranscriptionEngine {
    func supportedLocales() async -> [Locale] {
        [Locale(identifier: "en-US")]
    }

    func transcribe(
        audioAt url: URL,
        locale: Locale,
        trackID: UUID,
        progress: @escaping @Sendable (TranscriptionActivity) -> Void
    ) async throws -> [SubtitleCue] {
        progress(.preparingLanguage(0.5))
        try await Task.sleep(for: .seconds(60))
        return []
    }

    func progressiveTranscription(
        audioAt url: URL,
        locale: Locale,
        trackID: UUID,
        startingAt time: TimeInterval,
        progress: @escaping @Sendable (TranscriptionActivity) -> Void
    ) -> AsyncThrowingStream<SubtitleCue, Error> {
        AsyncThrowingStream { continuation in
            progress(.recognizing)
            continuation.yield(
                SubtitleCue(
                    startTime: time,
                    endTime: time + 1,
                    text: "Live cue",
                    trackID: trackID
                )
            )
            continuation.finish()
        }
    }
}

@MainActor
private final class PlaybackEngineSpy: PlaybackEngine {
    let renderView = NSView()
    var eventHandler: ((PlaybackEngineEvent) -> Void)?
    private(set) var currentURL: URL?
    private(set) var openCount = 0
    var state = PlaybackState()
    private(set) var volume: Float?
    private(set) var isMuted: Bool?
    private(set) var playbackRate: Float?
    private(set) var videoScalingMode: VideoScalingMode?
    private(set) var aspectRatio: VideoRatio?
    private(set) var cropRatio: VideoRatio?
    private(set) var rotation: VideoRotation?
    private(set) var hardwareDecoding: Bool?
    private(set) var deinterlacing: Bool?
    private(set) var videoEqualizer: VideoEqualizer?
    var availableAudioTracks: [AudioTrack] = []
    private(set) var selectedAudioTrackID: Int64?
    private(set) var audioDelay: TimeInterval?
    private(set) var seekTime: TimeInterval?
    private(set) var seekExact: Bool?
    private(set) var skipInterval: TimeInterval?
    private(set) var loopA: TimeInterval?
    private(set) var loopB: TimeInterval?

    func open(_ url: URL) {
        currentURL = url
        openCount += 1
    }

    func playbackClock() -> (time: TimeInterval, duration: TimeInterval, isPlaying: Bool) {
        (state.currentTime, state.duration, state.isPlaying)
    }

    func play() {
        state.isPlaying = true
    }

    func pause() {
        state.isPlaying = false
    }

    func seek(to time: TimeInterval, exact: Bool) {
        seekTime = time
        seekExact = exact
    }

    func skip(by interval: TimeInterval) {
        skipInterval = interval
    }

    func setVolume(_ volume: Float) {
        self.volume = volume
        state.volume = volume
    }

    func setMuted(_ isMuted: Bool) {
        self.isMuted = isMuted
        state.isMuted = isMuted
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
    }

    func setVideoScalingMode(_ mode: VideoScalingMode) {
        videoScalingMode = mode
    }

    func setAspectRatio(_ ratio: VideoRatio) {
        aspectRatio = ratio
    }

    func setCropRatio(_ ratio: VideoRatio) {
        cropRatio = ratio
    }

    func setRotation(_ rotation: VideoRotation) {
        self.rotation = rotation
    }

    func setHardwareDecoding(_ isEnabled: Bool) {
        hardwareDecoding = isEnabled
    }

    func setDeinterlacing(_ isEnabled: Bool) {
        deinterlacing = isEnabled
    }

    func setVideoEqualizer(_ equalizer: VideoEqualizer) {
        videoEqualizer = equalizer
    }

    func audioTracks() -> [AudioTrack] {
        availableAudioTracks
    }

    func subtitleStreams() -> [SubtitleStream] {
        []
    }

    func selectAudioTrack(_ id: Int64) {
        selectedAudioTrackID = id
    }

    func setAudioDelay(_ delay: TimeInterval) {
        audioDelay = delay
    }

    func chapters() -> [PlaybackChapter] {
        []
    }

    func cycleABLoop(at time: TimeInterval) {
        if loopA == nil {
            loopA = time
        } else if loopB == nil {
            loopB = time
        } else {
            clearABLoop()
        }
    }

    func clearABLoop() {
        loopA = nil
        loopB = nil
    }
}
