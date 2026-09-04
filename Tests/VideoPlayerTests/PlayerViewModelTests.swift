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
}

@MainActor
private final class PlaybackEngineSpy: PlaybackEngine {
    let renderView = NSView()
    private(set) var currentURL: URL?

    func open(_ url: URL) {
        currentURL = url
    }

    func play() {}
    func pause() {}
}

