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

    func testControlsAreForwardedToPlaybackEngine() {
        let engine = PlaybackEngineSpy()
        let viewModel = PlayerViewModel(playbackEngine: engine)

        viewModel.setVolume(0.4)
        viewModel.setMuted(true)
        viewModel.setPlaybackRate(1.5)
        viewModel.setVideoScalingMode(.fill)
        viewModel.seek(to: 42)
        viewModel.skip(by: 10)

        XCTAssertEqual(engine.volume, 0.4)
        XCTAssertEqual(engine.isMuted, true)
        XCTAssertEqual(engine.playbackRate, 1.5)
        XCTAssertEqual(engine.videoScalingMode, .fill)
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
}
