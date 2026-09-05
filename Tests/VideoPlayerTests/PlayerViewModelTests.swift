import AppKit
import XCTest
@testable import VideoPlayer

@MainActor
final class PlayerViewModelTests: XCTestCase {
    func testOpeningVideoUpdatesEngineAndViewModel() {
        let engine = PlaybackEngineSpy()
        let viewModel = PlayerViewModel(playbackEngine: engine)
        let url = URL(fileURLWithPath: "/tmp/example.mp4")

        viewModel.open(url)

        XCTAssertEqual(engine.currentURL, url)
        XCTAssertEqual(viewModel.currentURL, url)
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
        XCTAssertEqual(engine.seekTime, 42)
        XCTAssertEqual(engine.skipInterval, 10)
    }

    func testMuteTogglePreservesVolume() {
        let engine = PlaybackEngineSpy()
        engine.state.volume = 0.4
        let viewModel = PlayerViewModel(playbackEngine: engine)
        viewModel.refreshPlaybackState()

        viewModel.toggleMuted()

        XCTAssertTrue(viewModel.playbackState.isMuted)
        XCTAssertEqual(viewModel.playbackState.volume, 0.4)

        viewModel.toggleMuted()

        XCTAssertFalse(viewModel.playbackState.isMuted)
        XCTAssertEqual(viewModel.playbackState.volume, 0.4)
    }

    func testSubtitleStylesPersistBetweenViewModels() {
        let suiteName = "PlayerViewModelTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let style = SubtitleStyle(
            fontSize: 36,
            textColor: .cyan,
            backgroundOpacity: 0.4,
            bottomPadding: 210
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
}

private struct TranscriptionEngineStub: TranscriptionEngine {
    func supportedLocales() async -> [Locale] {
        [Locale(identifier: "en-US")]
    }

    func transcribe(audioAt url: URL, locale: Locale, trackID: UUID) async throws -> [SubtitleCue] {
        []
    }

    func progressiveTranscription(
        audioAt url: URL,
        locale: Locale,
        trackID: UUID,
        startingAt time: TimeInterval
    ) -> AsyncThrowingStream<SubtitleCue, Error> {
        AsyncThrowingStream { continuation in
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
    private(set) var currentURL: URL?
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
    private(set) var seekTime: TimeInterval?
    private(set) var skipInterval: TimeInterval?

    func open(_ url: URL) {
        currentURL = url
    }

    func play() {}
    func pause() {}

    func seek(to time: TimeInterval) {
        seekTime = time
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
}
